defmodule ResourceCache.Compiler do
  alias ResourceCache.{CacheManager, CallbackManager, Changeset, Config}
  import ResourceCache.Utility
  require Logger
  @update_timeout 30_000

  @callback update(module, ResourceCache.Changeset.t()) :: :ok | {:error, atom}
  @callback generate(ResourceCache.Config.t()) :: term

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour unquote(__MODULE__)
    end
  end

  @spec generate(ResourceCache.Config.t()) :: term
  def generate(config)

  def generate(config = %ResourceCache.Config{}) do
    impl = Config.implementation(config)
    implement(config)

    quote do
      unquote(getters(config))

      unquote(spec(:list, [], spec_list(spec_type(config.resource)), nil))
      @doc unquote(list_doc(config))
      def list, do: unquote(impl).list()

      unquote(generic(config))
    end
  end

  @spec implement(ResourceCache.Config.t()) :: :ok
  def implement(config)

  def implement(config = %ResourceCache.Config{type: type}) do
    Code.compile_quoted(
      quote do
        defmodule unquote(Config.implementation(config)) do
          @moduledoc false
          unquote(compiler(type).generate(config))
        end
      end
    )

    :ok
  end

  defp getters(config)

  defp getters(config = %ResourceCache.Config{indices: indices}) do
    impl = Config.implementation(config)
    primary = Enum.find(indices, & &1.primary)

    primary_get =
      if primary do
        quote do
          unquote(decorate_get(config, primary, :get))
          defdelegate get(id), to: unquote(impl)
        end
      end

    get =
      Enum.reduce(indices, primary_get, fn
        index, acc ->
          func = :"get_by_#{index.index}"

          quote do
            unquote(acc)

            unquote(decorate_get(config, index))
            defdelegate unquote(func)(v), to: unquote(impl)
          end
      end)

    quote do
      unquote(get)
      unquote(get_by_alias(config))
    end
  end

  defp get_by_alias(config)

  defp get_by_alias(config = %ResourceCache.Config{indices: indices}) do
    impl = Config.implementation(config)

    Enum.reduce(
      indices,
      decorate_get_by(config),
      fn %{index: field}, acc ->
        quote do
          unquote(acc)

          def get_by([{unquote(field), value}]),
            do: unquote(impl).unquote(:"get_by_#{field}")(value)
        end
      end
    )
  end

  def update(cache, data)

  def update(cache, data) do
    GenServer.call(__MODULE__, {:update, cache, data})
  end

  defp compiler(type)
  defp compiler(:direct), do: ResourceCache.Compilers.Direct
  defp compiler(:ets), do: ResourceCache.Compilers.ETS
  defp compiler(:hardcoded), do: ResourceCache.Compilers.Hardcoded
  defp compiler(_), do: ResourceCache.Compilers.Hardcoded

  defp generate_filter(config, name, pre) do
    filters =
      config.module
      |> Module.get_attribute(:cache_filters, [])
      |> Enum.filter(&(elem(&1, 1) == pre))
      |> Enum.map(&elem(&1, 0))

    case filters do
      [] ->
        quote do
          defp unquote(name)(_), do: true
        end

      [h | t] ->
        sum =
          Enum.reduce(
            t,
            quote do
              unquote(h)(resource)
            end,
            fn filter, acc ->
              quote do
                unquote(acc) and unquote(filter)
              end
            end
          )

        quote do
          defp unquote(name)(resource), do: unquote(sum)
        end
    end
  end

  defp generate_optimize(config) do
    case Module.get_attribute(config.module, :cache_optimizers, []) do
      [] ->
        quote do
          defp __optimize__(resource), do: resource
        end

      [h | t] ->
        chain =
          Enum.reduce(
            t,
            quote do
              resource |> unquote(h)()
            end,
            fn filter, acc ->
              quote do
                unquote(acc) |> unquote(filter)()
              end
            end
          )

        quote do
          defp __optimize__(resource), do: unquote(chain)
        end
    end
  end

  defp generic(config) do
    mdoc =
      unless Module.get_attribute(config.module, :moduledoc) do
        quote do
          @moduledoc ~S"""
          TODO GENERATE SOME DOCS
          """
        end
      end

    quote do
      unquote(mdoc)
      @doc false
      @impl ResourceCache
      @spec __config__ :: module
      def __config__,
        do: Application.get_env(:resource_cache, __MODULE__, unquote(Macro.escape(config)))

      @doc false
      @impl ResourceCache
      @spec __config__(:callbacks) :: module
      def __config__(:callbacks) do
        unquote(ResourceCache.CallbackManager).callbacks(__MODULE__)
      end

      @doc false
      @spec __initialized__ :: boolean
      def __initialized__

      def __initialized__,
        do: Application.get_env(:resource_cache, unquote(:"cache_init_#{config.module}"), false)

      @doc false
      @impl ResourceCache
      @spec __process__([term]) :: [term]
      def __process__(data) do
        data
        |> unquote(__MODULE__).filter(&__pre_filter__/1)
        |> unquote(__MODULE__).map(&__convert__/1)
        |> unquote(__MODULE__).filter(&__post_filter__/1)
        |> unquote(__MODULE__).map(&__optimize__/1)
      end

      @spec __optimize__(term) :: term
      defp __optimize__(resource)
      unquote(generate_optimize(config))

      @spec __pre_filter__(term) :: boolean
      defp __pre_filter__(resource)
      unquote(generate_filter(config, :__pre_filter__, true))

      @spec __post_filter__(term) :: boolean
      defp __post_filter__(resource)
      unquote(generate_filter(config, :__post_filter__, false))

      @doc false
      @impl ResourceCache
      @spec __type__ :: :cache
      def __type__, do: :cache

      @doc ~S"""
      The currently connected cache source.
      """
      @spec source :: module | nil
      def source
      def source, do: unquote(CacheManager).source(__MODULE__)

      @doc ~S"""
      Set a new source for the cache.

      ## Example

      ```elixir
      iex> configure(source: :ets)
      :ok
      ```
      """
      @spec configure(opts :: Keyword.t()) :: :ok | {:error, atom}
      def configure(opts \\ [])

      def configure(opts) do
        with {:ok, config} <- unquote(Config).update(__config__(), opts) do
          Application.put_env(:resource_cache, __MODULE__, config, persistent: true)
          {s, o} = config.source

          unquote(CacheManager).configure(__MODULE__, s, o)
        end
      end
    end
  end

  ### Compile Server ###

  use GenServer

  @doc false
  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts)
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  @impl GenServer
  @spec init(any) :: {:ok, %{}}
  def init(opts)
  def init(_), do: {:ok, %{}}

  @doc false
  @impl GenServer
  def handle_call(request, from, state)

  def handle_call({:update, cache, data}, _from, state) do
    new_state =
      case Map.get(state, cache) do
        {:updating, timer} ->
          Map.put(state, cache, {:pending, timer, data})

        {:pending, timer, _data} ->
          Map.put(state, cache, {:pending, timer, data})

        nil ->
          Map.put(state, cache, start_update(cache, data))
      end

    {:reply, :ok, new_state}
  end

  @doc false
  @impl GenServer
  def handle_info(msg, state)

  def handle_info({:update_finished, cache}, state) do
    case Map.get(state, cache) do
      nil ->
        Logger.debug("[ResourceCache] Compiler encountered invalid queue state.")
        {:noreply, state}

      {:updating, timer} ->
        Process.cancel_timer(timer)
        {:noreply, Map.delete(state, cache)}

      {:pending, timer, data} ->
        Process.cancel_timer(timer)
        {:noreply, Map.put(state, cache, start_update(cache, data))}
    end
  end

  def handle_info({:update_timeout, cache}, state) do
    Logger.warn(fn -> "[ResourceCache] Compilation of #{inspect(cache)} timed out." end)
    handle_info({:update_finished, cache}, state)
  end

  @doc false
  @spec do_update(cache :: module, data :: term) :: :ok
  def do_update(cache, data) do
    compiler = compiler(cache.__config__().type)
    d = cache.__process__(data)

    CallbackManager.pre_update(cache, d)
    {:ok, changeset} = Changeset.generate(cache, d)
    compiler.update(cache, changeset)
    Application.put_env(:resource_cache, :"cache_init_#{cache}", true)

    send(__MODULE__, {:update_finished, cache})
    CallbackManager.update(cache, changeset)

    :ok
  end

  defp start_update(cache, data) do
    spawn(__MODULE__, :do_update, [cache, data])
    timer = Process.send_after(self(), {:update_timeout, cache}, @update_timeout)
    {:updating, timer}
  end

  @spec filter([map], (map -> boolean), [map]) :: [map]
  def filter(data, filter, acc \\ [])
  def filter([], _filter, acc), do: acc

  def filter([h | t], filter, acc) do
    if filter.(h),
      do: filter(t, filter, [h | acc]),
      else: filter(t, filter, acc)
  rescue
    _ -> filter(t, filter, acc)
  end

  @spec map([map], (map -> map), [map]) :: [map]
  def map(data, mapper, acc \\ [])
  def map([], _mapper, acc), do: acc

  def map([h | t], mapper, acc) do
    map(t, mapper, [mapper.(h) | acc])
  rescue
    _ -> map(t, mapper, acc)
  end
end
