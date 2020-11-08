defmodule ResourceCache.CacheManager do
  use GenServer
  alias ResourceCache.{CallbackManager, Callbacks, Compiler, PollManager, Source}

  @caches :resource_caches
  @sources :resource_cache_source

  @typep cache_entry :: {cache :: module, source :: module, fingerprint :: Source.fingerprint()}

  @spec source_fingerprint(cache :: module) ::
          {source :: module, fingerprint :: Source.fingerprint()} | nil
  def source_fingerprint(cache)

  def source_fingerprint(cache) do
    case :ets.lookup(@caches, cache) do
      [{_cache, source, fingerprint}] -> {source, fingerprint}
      _ -> nil
    end
  end

  @spec fingerprint(cache :: module) :: Source.fingerprint() | nil
  def fingerprint(cache)

  def fingerprint(cache) do
    case :ets.lookup(@caches, cache) do
      [{_cache, _source, fingerprint}] -> fingerprint
      _ -> nil
    end
  end

  @spec source(cache :: module) :: module | nil
  def source(cache)

  def source(cache) do
    case :ets.lookup(@caches, cache) do
      [{_cache, source, _fingerprint}] -> source
      _ -> nil
    end
  end

  @spec source_updated(source :: module, fingerprint :: Source.fingerprint()) :: :ok
  def source_updated(source, fingerprint)

  def source_updated(source, fingerprint) do
    # Keep sync for now
    data = source.list(fingerprint, true)

    source
    |> caches(fingerprint)
    |> Enum.each(&Compiler.update(&1, data))
  end

  @spec state(source :: module, fingerprint :: Source.fingerprint()) :: term
  def state(source, fingerprint)

  def state(source, fingerprint) do
    case :ets.lookup(@sources, {source, fingerprint}) do
      [{{_source, _fingerprint}, state}] -> state
      _ -> nil
    end
  end

  @spec preload(cache :: module, source :: module, opts :: Keyword.t()) :: :ok | {:error, atom}
  def preload(cache, source, opts \\ [])

  def preload(cache, source, opts) do
    :application.ensure_all_started(:resource_cache)

    if mod = Process.whereis(__MODULE__) do
      send(mod, {:preload, cache, source, opts})
    else
      auto_load = Application.get_env(:resource_cache, :auto_load, [])
      updated = [{cache, source, opts} | Enum.reject(auto_load, &(elem(&1, 0) == cache))]
      Application.put_env(:resource_cache, :auto_load, updated, persistent: true)

      :ok
    end
  end

  @spec configure(cache :: module, source :: module, opts :: Keyword.t()) :: :ok | {:error, atom}
  def configure(cache, source, opts \\ [])

  def configure(cache, source, opts) do
    GenServer.call(__MODULE__, {:configure, cache, source, opts})
  end

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts \\ [])
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_) do
    :ets.new(@caches, [:set, :named_table, :public, read_concurrency: true])

    auto_load = Application.get_env(:resource_cache, :auto_load, [])

    Enum.reduce(auto_load, {:ok, %{}}, fn {cache, source, opts}, {:ok, acc} ->
      do_configure(acc, cache, source, opts)
    end)
  end

  @impl GenServer
  def handle_call(request, from, state)

  def handle_call({:configure, cache, source, opts}, _from, state) do
    with {:ok, new_state} <- do_configure(state, cache, source, opts) do
      {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_info(msg, state)

  def handle_info({:preload, cache, source, opts}, state) do
    {:ok, new_state} = do_configure(state, cache, source, opts)
    {:noreply, new_state}
  end

  def handle_info({:configured, fingerprint}, state) do
    {caches, new_state} = Map.pop(state, fingerprint, [])
    Enum.each(caches, &CallbackManager.configure/1)

    {:noreply, new_state}
  end

  defp prepare_cache_configure(cache, source, opts)

  defp prepare_cache_configure(cache, source, opts) do
    {interval, opts} = Keyword.pop(opts, :interval, 60_000)

    fingerprint = source.fingerprint(cache, opts)
    PollManager.monitor(cache, source, fingerprint, interval)

    case cache(cache) do
      nil ->
        {:ok, fingerprint}

      {_cache, ^source, ^fingerprint} ->
        :ok

      {_cache, previous_source, previous_fingerprint} ->
        PollManager.forget(cache, previous_source, previous_fingerprint)

        with :ok <- previous_source.release(cache, previous_fingerprint),
             do: {:ok, fingerprint}
    end
  end

  defp do_configure(state, cache, source, opts) do
    {callbacks, opts} = Callbacks.from_opts(opts)

    CallbackManager.set_callbacks(cache, callbacks)

    case prepare_cache_configure(cache, source, opts) do
      {:ok, fingerprint} ->
        if Map.has_key?(state, fingerprint) do
          {:ok, Map.update!(state, fingerprint, &if(cache in &1, do: &1, else: [cache | &1]))}
        else
          me = self()

          call = fn ->
            send(me, {:configured, fingerprint})
            :unhook
          end

          CallbackManager.set_callbacks(cache, on_update: call)
          spawn_link(fn -> async_configure(cache, source, fingerprint, opts) end)

          {:ok, Map.put(state, fingerprint, [cache])}
        end

      :ok ->
        CallbackManager.configure(cache)
        {:ok, state}
    end
  end

  defp async_configure(cache, source, fingerprint, opts) do
    with :ok <- source.init(cache, fingerprint, opts),
         true <- :ets.insert(@caches, {cache, source, fingerprint}) do
      data = source.list(fingerprint, true)
      Compiler.update(cache, data)
    end
  end

  ### Helpers ###

  @spec cache(cache :: module) :: cache_entry | nil
  defp cache(cache)

  defp cache(cache) do
    case :ets.lookup(@caches, cache) do
      [entry] -> entry
      _ -> nil
    end
  end

  @spec caches(source :: module, fingerprint :: Source.fingerprint()) :: [module]
  defp caches(source, fingerprint)

  defp caches(source, fingerprint) do
    @caches
    |> :ets.match({:"$1", source, fingerprint})
    |> Enum.map(fn [a] -> a end)
  end
end
