defmodule ResourceCache.CallbackManager do
  use GenServer
  alias ResourceCache.Callbacks

  @spec callbacks(cache :: module) :: ResourceCache.Callbacks.t()
  def callbacks(cache)
  def callbacks(cache), do: GenServer.call(__MODULE__, {:callbacks, cache})

  @spec unhook(cache :: module, hooks :: fun | [fun]) :: :ok
  def unhook(cache, fun)
  def unhook(cache, fun) when is_list(fun), do: GenServer.call(__MODULE__, {:unhook, cache, fun})
  def unhook(cache, fun), do: GenServer.call(__MODULE__, {:unhook, cache, [fun]})

  @spec set_callbacks(cache :: module, callbacks :: ResourceCache.Callbacks.t() | Keyword.t()) ::
          :ok
  def set_callbacks(cache, callbacks)

  def set_callbacks(cache, callbacks = %ResourceCache.Callbacks{}) do
    GenServer.cast(__MODULE__, {:set_callbacks, cache, callbacks})
  end

  def set_callbacks(cache, opts) do
    {cb, _} = Callbacks.from_opts(opts)

    if Callbacks.empty?(cb) do
      :ok
    else
      set_callbacks(cache, cb)
    end
  end

  @spec configure(cache :: module) :: :ok
  def configure(cache)

  def configure(cache) do
    GenServer.cast(__MODULE__, {:configure, cache})
  end

  @spec pre_update(module, [ResourceCache.resource()]) :: :ok
  def pre_update(cache, data)

  def pre_update(cache, data) do
    GenServer.cast(__MODULE__, {:pre_update, cache, data})
  end

  @spec update(module, ResourceCache.Changeset.t()) :: :ok
  def update(cache, changeset)

  def update(cache, changeset) do
    GenServer.cast(__MODULE__, {:update, cache, changeset})
  end

  def start_link(opts \\ [])
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(opts)
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  def handle_call(request, from, state)

  def handle_call({:callbacks, cache}, _from, state) do
    {:reply, callbacks(state, cache), state}
  end

  def handle_call({:unhook, cache, hooks}, _from, state) do
    new_state =
      case Map.get(state, cache) do
        nil -> state
        callbacks -> Map.put(state, cache, Callbacks.unhook(callbacks, hooks))
      end

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_cast(request, state)

  def handle_cast({:set_callbacks, cache, callbacks}, state) do
    c = callbacks(state, cache)

    cb = Callbacks.merge(c, callbacks)
    {:noreply, Map.put(state, cache, cb)}
  end

  def handle_cast({:configure, cache}, state) do
    c = callbacks(state, cache)

    {:ok, cb} = Callbacks.configure(c, cache)
    {:noreply, Map.put(state, cache, cb)}
  end

  def handle_cast({:pre_update, cache, data}, state) do
    c = callbacks(state, cache)

    {:ok, cb} = Callbacks.pre_update(c, cache, data)
    {:noreply, Map.put(state, cache, cb)}
  end

  def handle_cast({:update, cache, changeset}, state) do
    c = callbacks(state, cache)

    {:ok, cb} = Callbacks.update(c, cache, changeset)
    {:noreply, Map.put(state, cache, cb)}
  end

  @spec callbacks(map, module) :: ResourceCache.Callbacks.t()
  defp callbacks(state, cache)

  defp callbacks(state, cache) do
    case Map.get(state, cache) do
      nil -> Callbacks.sanitize(cache.__config__().callbacks)
      cb -> cb
    end
  end
end
