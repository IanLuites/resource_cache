defmodule ResourceCache.Callbacks do
  @type configure_hook :: (() -> :ok | :unhook)
  @type init_hook :: (cache :: module -> :ok | :unhook)
  @type pre_update_hook :: (cache :: module, data :: [ResourceCache.resource()] -> :ok | :unhook)

  @type t :: %__MODULE__{
          configure: [ResourceCache.Callbacks.configure_hook()],
          init: [ResourceCache.Callbacks.init_hook()],
          pre_update: [ResourceCache.Callbacks.pre_update_hook()],
          update: [ResourceCache.hook()]
        }

  defstruct configure: [], init: [], pre_update: [], update: []

  @spec empty?(ResourceCache.Callbacks.t()) :: boolean
  def empty?(%__MODULE__{configure: [], init: [], pre_update: [], update: []}), do: true
  def empty?(_), do: false

  @spec from_opts(Keyword.t()) :: {ResourceCache.Callbacks.t(), opts :: Keyword.t()}
  def from_opts(opts)

  def from_opts(opts) do
    {configure, opts} = Keyword.pop(opts, :on_configure)
    {pre_update, opts} = Keyword.pop(opts, :pre_update)
    {callback, opts} = Keyword.pop(opts, :callback)
    {update, opts} = Keyword.pop(opts, :on_update)

    {%__MODULE__{
       configure: hooks(configure),
       pre_update: hooks(pre_update),
       update: hooks(callback) ++ hooks(update)
     }, opts}
  end

  @spec hooks(term) :: [term]
  defp hooks(hook)
  defp hooks(nil), do: []
  defp hooks(hooks) when is_list(hooks), do: hooks
  defp hooks(hook), do: [hook]

  @spec unhook(ResourceCache.Callbacks.t(), fun | [fun]) :: ResourceCache.Callbacks.t()
  def unhook(callbacks, hooks)

  def unhook(%__MODULE__{configure: c, init: i, pre_update: p, update: u}, hooks)
      when is_list(hooks) do
    %__MODULE__{
      configure: Enum.reject(c, &(&1 in hooks)),
      init: Enum.reject(i, &(&1 in hooks)),
      pre_update: Enum.reject(p, &(&1 in hooks)),
      update: Enum.reject(u, &(&1 in hooks))
    }
  end

  def unhook(callbacks, hook), do: unhook(callbacks, [hook])

  @spec sanitize(ResourceCache.Callbacks.t()) :: ResourceCache.Callbacks.t()
  def sanitize(callbacks)

  def sanitize(%__MODULE__{configure: c, init: i, pre_update: p, update: u}) do
    %__MODULE__{
      configure: Enum.map(c, &do_sanitize/1),
      init: Enum.map(i, &do_sanitize/1),
      pre_update: Enum.map(p, &do_sanitize/1),
      update: Enum.map(u, &do_sanitize/1)
    }
  end

  defp do_sanitize(hook)

  defp do_sanitize(hook = {:&, _, _}) do
    {cb, []} = Code.eval_quoted(hook)
    cb
  end

  defp do_sanitize(hook), do: hook

  @spec merge(ResourceCache.Callbacks.t(), ResourceCache.Callbacks.t()) ::
          ResourceCache.Callbacks.t()
  def merge(a, b)

  def merge(a, b) do
    b
    |> Map.take(~w(configure pre_update update)a)
    |> Enum.reduce(a, fn {field, value}, acc ->
      Map.update!(acc, field, &Enum.uniq(&1 ++ value))
    end)
  end

  @spec configure(ResourceCache.Callbacks.t(), module) :: {:ok, ResourceCache.Callbacks.t()}
  def configure(callbacks, cache)
  def configure(callbacks = %__MODULE__{configure: []}, _cache), do: {:ok, callbacks}

  def configure(callbacks = %__MODULE__{configure: hooks}, cache) do
    cleaned =
      hooks
      |> Enum.map(fn hook ->
        case :erlang.fun_info(hook)[:arity] do
          0 -> unless(call_hook(hook, []) == :unhook, do: hook)
          1 -> unless(call_hook(hook, [cache]) == :unhook, do: hook)
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, %{callbacks | configure: cleaned}}
  end

  @spec pre_update(ResourceCache.Callbacks.t(), module, [ResourceCache.resource()]) ::
          {:ok, ResourceCache.Callbacks.t()}
  def pre_update(callbacks, cache, data)
  def pre_update(callbacks = %__MODULE__{pre_update: []}, _cache, _data), do: {:ok, callbacks}

  def pre_update(callbacks = %__MODULE__{pre_update: hooks}, cache, data) do
    cleaned =
      hooks
      |> Enum.map(fn hook ->
        case :erlang.fun_info(hook)[:arity] do
          0 -> unless(call_hook(hook, []) == :unhook, do: hook)
          1 -> unless(call_hook(hook, [cache]) == :unhook, do: hook)
          2 -> unless(call_hook(hook, [cache, data]) == :unhook, do: hook)
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, %{callbacks | pre_update: cleaned}}
  end

  @spec update(ResourceCache.Callbacks.t(), module, ResourceCache.Changeset.t()) ::
          {:ok, ResourceCache.Callbacks.t()}
  def update(callbacks, cache, changeset)
  def update(callbacks = %__MODULE__{update: []}, _, _), do: {:ok, callbacks}

  def update(callbacks = %__MODULE__{update: hooks}, cache, changeset) do
    cleaned =
      hooks
      |> Enum.map(fn hook ->
        case :erlang.fun_info(hook)[:arity] do
          0 -> unless(call_hook(hook, []) == :unhook, do: hook)
          1 -> unless(call_hook(hook, [cache]) == :unhook, do: hook)
          2 -> unless(call_hook(hook, [cache, changeset]) == :unhook, do: hook)
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, %{callbacks | update: cleaned}}
  end

  defp call_hook(hook, args) do
    apply(hook, args)
  rescue
    _ -> :unhook
  end
end
