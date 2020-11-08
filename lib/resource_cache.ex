defmodule ResourceCache do
  @moduledoc ~S"""
  Fast caching with clear syntax.

  ## Quick Setup

  ```elixir
  def deps do
    [
      {:resource_cache, "~> 0.1"}
    ]
  end
  ```

  Define a cache by setting a resource (in this case Ecto schema)
  and source. (The Ecto repo to query.)
  ```elixir
  defmodule MyApp.Categories do
    use ResourceCache
    resource MyApp.Category
    source :ecto, repo: MyApp.Repo
  end
  ```

  Now the cache can be used for fast listing:
  ```elixir
  iex> MyApp.Categories.list()
  [%MyApp.Category{}, ...]
  ```

  Indices can be added to do quick lookups by value:
  ```elixir
  defmodule MyApp.Categories do
    use ResourceCache
    resource MyApp.Category
    source :ecto, repo: MyApp.Repo

    index :slug, primary: true
  end
  ```

  Now `get_by_slug/1` can be used.
  In addition to the standard `get_by_slug`,
  `get/1` is also available since it was defined as primary index.

  ```elixir
  iex> MyApp.Categories.get("electronics")
  %MyApp.Category{}
  iex> MyApp.Categories.get_by_slug("electronics")
  %MyApp.Category{}
  iex> MyApp.Categories.get("fake")
  nil
  iex> MyApp.Categories.get_by_slug("fake")
  nil
  ```

  There is no limit to the amount of indices that can be added.

  It is possible to pass an optional type for each index,
  to generate cleaner specs for the function arguments.

  ```elixir
  index :slug, primary: true, type: String.t
  ```
  """
  alias ResourceCache.Cache

  @callback __type__() :: :cache | :source | :bridge
  @callback __config__() :: module
  @callback __config__(:callbacks) :: term
  @callback __process__([term]) :: [term]

  @type resource :: %{optional(atom) => term}
  @type hook ::
          (cache :: module -> :ok | :unhook)
          | (cache :: module, changes :: ResourceCache.Changeset.t() -> nil)

  @doc false
  @spec __using__(Keyword.t()) :: term
  defmacro __using__(opts \\ []) do
    # Register
    Module.put_attribute(__CALLER__.module, :cache_type, Keyword.get(opts, :type))
    Module.register_attribute(__CALLER__.module, :cache_resource, accumulate: false)
    Module.register_attribute(__CALLER__.module, :cache_resource_type, accumulate: false)
    Module.register_attribute(__CALLER__.module, :cache_indices, accumulate: true)
    Module.register_attribute(__CALLER__.module, :cache_default_source, accumulate: false)
    Module.register_attribute(__CALLER__.module, :cache_filters, accumulate: true)
    Module.register_attribute(__CALLER__.module, :cache_optimizers, accumulate: true)
    Module.register_attribute(__CALLER__.module, :cache_on_configure, accumulate: true)
    Module.register_attribute(__CALLER__.module, :cache_pre_update, accumulate: true)
    Module.register_attribute(__CALLER__.module, :cache_on_update, accumulate: true)

    # Shorthands
    resource = Macro.expand(Keyword.get(opts, :resource), __CALLER__)
    source = Macro.expand(Keyword.get(opts, :source), __CALLER__)
    source_opts = Macro.expand(Keyword.get(opts, :source_opts), __CALLER__)

    quote do
      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      require unquote(__MODULE__)
      require unquote(__MODULE__.CacheManager)

      import unquote(__MODULE__),
        only: [
          filter: 1,
          filter: 2,
          filter: 3,
          index: 1,
          index: 2,
          on_configure: 1,
          on_update: 1,
          optimize: 1,
          optimize: 2,
          optimize: 3,
          reject: 1,
          reject: 2,
          reject: 3,
          resource: 1,
          resource: 2,
          resource: 3,
          source: 1,
          source: 2,
          type: 1,
          type: 2
        ]

      unquote(if resource, do: Cache.resource(__CALLER__, resource, [], []))
      unquote(if source, do: Cache.source(__CALLER__, source, source_opts))
    end
  end

  @spec __before_compile__(Macro.Env.t()) :: term
  defmacro __before_compile__(env), do: Cache.generate(env)

  @spec type(atom, Keyword.t()) :: term
  defmacro type(type, opts \\ []) do
    Cache.type(__CALLER__, type, opts)
  end

  @spec resource(module, Keyword.t(), term) :: term
  defmacro resource(resource, opts \\ [], convert \\ []) do
    {c, o} = opts_do(convert, opts)
    Cache.resource(__CALLER__, Macro.expand(resource, __CALLER__), c, o)
  end

  @spec source(module, Keyword.t()) :: term
  defmacro source(source, opts \\ []),
    do: Cache.source(__CALLER__, Macro.expand(source, __CALLER__), opts)

  @spec index(atom, Keyword.t()) :: term
  defmacro index(field, opts \\ []), do: Cache.index(__CALLER__, field, opts)

  @spec on_configure(ResourceCache.hook(), Keyword.t()) :: term
  defmacro on_configure(callback, opts \\ []), do: Cache.on_configure(__CALLER__, callback, opts)

  @spec on_update(ResourceCache.hook(), Keyword.t()) :: term
  defmacro on_update(callback, opts \\ []), do: Cache.on_update(__CALLER__, callback, opts)

  defmacro optimize(field \\ nil, opts \\ [], optimizer) do
    {optimize, o} = opts_do(optimizer, opts)
    Cache.optimize(__CALLER__, field, optimize, o)
  end

  @spec reject(atom | Keyword.t(), term) :: term
  defmacro reject(field_or_opts \\ [], rejecter)

  defmacro reject(input, rejecter) do
    field = if is_atom(input), do: input
    {rejecter, opts} = if is_list(input), do: opts_do(rejecter, input), else: opts_do(rejecter)

    Cache.reject(__CALLER__, field, rejecter, opts)
  end

  @spec reject(atom, Keyword.t(), term) :: term
  defmacro reject(field, opts, do: rejecter), do: Cache.reject(__CALLER__, field, rejecter, opts)
  defmacro reject(field, opts, rejecter), do: Cache.reject(__CALLER__, field, rejecter, opts)

  @spec filter(atom | Keyword.t(), term) :: term
  defmacro filter(field_or_opts \\ [], filter)

  defmacro filter(input, filter) do
    field = if is_atom(input), do: input
    {filter, opts} = if is_list(input), do: opts_do(filter, input), else: opts_do(filter)

    Cache.filter(__CALLER__, field, filter, opts)
  end

  @spec filter(atom, Keyword.t(), term) :: term
  defmacro filter(field, opts, do: filter), do: Cache.filter(__CALLER__, field, filter, opts)
  defmacro filter(field, opts, filter), do: Cache.filter(__CALLER__, field, filter, opts)

  @spec opts_do(term | Keyword.t(), Keyword.t()) :: {term, Keyword.t()}
  defp opts_do(block_or_opts, opts \\ [])

  defp opts_do(block_or_opts, opts) when is_list(block_or_opts) and is_list(opts) do
    case Keyword.pop(block_or_opts, :do) do
      {nil, o} -> o |> Keyword.merge(opts) |> Keyword.pop(:do)
      {block, o} -> {block, Keyword.merge(o, opts)}
    end
  end

  defp opts_do(block, opts) when is_list(opts), do: {block, opts}
  defp opts_do(block, opts) when is_list(block), do: {opts, block}
end
