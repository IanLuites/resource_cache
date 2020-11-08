defmodule ResourceCache.Config do
  @moduledoc false
  alias ResourceCache.{CallbackManager, Callbacks}

  defmodule Index do
    @moduledoc false

    @typedoc @moduledoc
    @type t :: %__MODULE__{
            index: atom,
            type: term,
            primary: boolean,
            order: fun(),
            doc: String.t() | nil
          }

    defstruct [:index, :type, :primary, :order, :doc]
  end

  @typedoc @moduledoc
  @type t :: %__MODULE__{
          module: module,
          type: :ets | :hardcoded,
          resource: module,
          as: module | nil,
          source: {module, Keyword.t()} | nil,
          indices: [ResourceCache.Config.Index.t()],
          callbacks: ResourceCache.Callbacks.t()
        }

  defstruct [:module, :type, :resource, :as, :source, :indices, :callbacks]

  @doc ~S"""

  """
  @spec resource(ResourceCache.Config.t()) :: module
  def resource(%__MODULE__{resource: r, as: a}), do: a || r

  @spec implementation(ResourceCache.Config.t()) :: module
  def implementation(%__MODULE__{module: m}), do: Module.concat(m, :__Cache__)

  @doc ~S"""
  Validate a resource cache config.

  Emits warnings and errors in case the config contains errors.
  """
  @spec validate(ResourceCache.Config.t()) ::
          {:ok, ResourceCache.Config.t()} | {:error, atom, Keyword.t()}
  def validate(config)

  def validate(config = %__MODULE__{module: m, resource: r, source: s}) do
    if r do
      case s do
        nil ->
          {:ok, config}

        {mod, v} ->
          with {:ok, s, o} <- validate_source(mod, v), do: {:ok, %{config | source: {s, o}}}

        _ ->
          {:ok, config}
      end
    else
      # raise CompileError, description: "[ResourceCache] Missing resource on #{inspect(m)}."
      {:error, :missing_resource, description: "Missing resource on #{inspect(m)}"}
    end
  end

  @spec update(ResourceCache.Config.t(), Keyword.t()) :: :ok | {:ok, ResourceCache.Config.t()}
  def update(config, opts \\ [])
  def update(_config, []), do: :ok

  def update(config, opts) do
    {type, opts} = Keyword.pop(opts, :type)
    {source, opts} = Keyword.pop(opts, :source)
    {unhook, opts} = Keyword.pop(opts, :unhook)
    {callbacks, opts} = Callbacks.from_opts(opts)
    s = if(source, do: {source, opts})

    {changed?, config} = Enum.reduce([type: type, source: s], {false, config}, &maybe_update/2)

    unless Callbacks.empty?(callbacks) do
      CallbackManager.set_callbacks(config.module, callbacks)
    end

    if unhook do
      CallbackManager.unhook(config.module, unhook)
    end

    if changed?, do: validate(config), else: :ok
  end

  defp maybe_update(change, acc)
  defp maybe_update({_field, nil}, acc), do: acc

  defp maybe_update({field, value}, acc = {_, config}) do
    if Map.get(config, field) == value,
      do: acc,
      else: {true, Map.put(config, field, value)}
  end

  defp validate_source(source, opts)
  defp validate_source(:ecto, opts), do: {:ok, ResourceCache.Sources.Ecto, opts}
  defp validate_source(:ets, opts), do: {:ok, ResourceCache.Sources.ETS, opts}

  defp validate_source(source, opts) do
    case source.__type__() do
      :cache -> {:ok, ResourceCache.Sources.Cache, Keyword.put(opts, :cache, source)}
      :source -> {:ok, source, opts}
    end
  rescue
    _ -> {:error, :invalid_cache_source}
  end
end
