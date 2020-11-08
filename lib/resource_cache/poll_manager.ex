defmodule ResourceCache.PollManager do
  use GenServer
  alias ResourceCache.CacheManager
  require Logger

  @timeout 30_000

  @spec monitor(
          cache :: module,
          monitor :: module,
          fingerprint :: ResourceCache.CacheManager.fingerprint(),
          interval :: pos_integer()
        ) :: :ok | {:error, atom}
  def monitor(cache, source, fingerprint, interval)

  def monitor(cache, source, fingerprint, interval) do
    if source.__config__().type == :poll do
      GenServer.call(__MODULE__, {:monitor, cache, source, fingerprint, interval})
    else
      :ok
    end
  end

  @spec forget(
          cache :: module,
          monitor :: module,
          fingerprint :: ResourceCache.CacheManager.fingerprint()
        ) :: :ok | {:error, atom}
  def forget(cache, source, fingerprint)

  def forget(cache, source, fingerprint) do
    if source.__config__().type == :poll do
      GenServer.call(__MODULE__, {:forget, cache, source, fingerprint})
    else
      :ok
    end
  end

  def start_link(opts)
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(opts)
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  def handle_call(request, from, state)

  def handle_call({:monitor, cache, source, fingerprint, interval}, _from, state) do
    base = %{caches: %{cache => interval}, timer: nil, interval: interval}

    new_state =
      case Map.get(state, source) do
        nil ->
          state
          |> Map.put(source, %{fingerprint => base})
          |> queue_poll(source, fingerprint)

        %{^fingerprint => %{caches: caches, interval: i}} ->
          cache_interval = Map.get(caches, cache)

          cond do
            cache_interval == interval ->
              state

            cache_interval != nil ->
              new_caches = Map.put(caches, cache, interval)
              interval = recalculate_interval(new_caches)

              state
              |> put_in([source, fingerprint, :caches], new_caches)
              |> put_in([source, fingerprint, :interval], interval)

            :new_cache ->
              state
              |> put_in([source, fingerprint, :caches, cache], interval)
              |> put_in([source, fingerprint, :interval], min(i, interval))
          end

        s ->
          state
          |> Map.put(source, Map.put(s, fingerprint, base))
          |> queue_poll(source, fingerprint)
      end

    {:reply, :ok, new_state}
  end

  def handle_call({:forget, cache, source, fingerprint}, _from, state) do
    new_state =
      case Map.get(state, source) do
        source_state = %{^fingerprint => %{caches: caches = %{^cache => c_i}, interval: i}} ->
          new_caches = Map.delete(caches, cache)

          cond do
            Enum.empty?(new_caches) ->
              {%{timer: t}, new_source_state} = Map.pop(source_state, fingerprint)

              # Make sure to cancel the timer if still running
              t && Process.cancel_timer(t)

              if Enum.empty?(source_state),
                do: Map.delete(state, source),
                else: Map.put(state, source, new_source_state)

            # Definitely wasn't the lowest interval so just updated caches and be done
            c_i > i ->
              put_in(state, [source, fingerprint, :caches], new_caches)

            # Recalculate because this might have been the lowest interval
            c_i == i ->
              state
              |> put_in([source, fingerprint, :caches], new_caches)
              |> put_in([source, fingerprint, :interval], recalculate_interval(new_caches))
          end

        _ ->
          state
      end

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(msg, state)

  def handle_info({:poll_done, source, fingerprint}, state) do
    # Check if we're still polling this one
    if get_in(state, [source, fingerprint]) do
      timer = get_in(state, [source, fingerprint, :timer])
      timer && Process.cancel_timer(timer)

      new_state = put_in(state, [source, fingerprint, :timer], nil)

      {:noreply, queue_poll(new_state, source, fingerprint)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:poll_timeout, source, fingerprint}, state) do
    # Check if we're still polling this one
    if get_in(state, [source, fingerprint]) do
      Logger.warn(fn -> "[ResourceCache] Poll of #{inspect(source)} timed out." end)
      {:noreply, queue_poll(state, source, fingerprint)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:poll, source, fingerprint}, state) do
    # Check if we're still polling this one
    if get_in(state, [source, fingerprint]) do
      ref = poll(source, fingerprint)
      {:noreply, put_in(state, [source, fingerprint, :timer], ref)}
    else
      {:noreply, state}
    end
  end

  @spec recalculate_interval(map) :: pos_integer()
  defp recalculate_interval(caches)
  defp recalculate_interval(%{caches: c = %{}}), do: recalculate_interval(c)
  defp recalculate_interval(caches), do: caches |> Map.values() |> Enum.min()

  @spec queue_poll(map, module, term) :: map
  defp queue_poll(state, source, fingerprint)

  defp queue_poll(state, source, fingerprint) do
    case get_in(state, [source, fingerprint]) do
      nil ->
        Logger.error("[ResourceCache] Watch for #{inspect(source)} does not exist.",
          source: source,
          fingerprint: fingerprint
        )

        state

      %{timer: nil, interval: timeout} ->
        timer = Process.send_after(self(), {:poll, source, fingerprint}, timeout)
        put_in(state, [source, fingerprint, :timer], timer)

      %{timer: _, interval: interval} ->
        Logger.warn("[ResourceCache] Poll of #{inspect(source)} already set.",
          source: source,
          fingerprint: fingerprint,
          interval: interval
        )

        state
    end
  end

  @spec poll(source :: module, fingerprint :: term) :: reference
  defp poll(source, fingerprint)

  defp poll(source, fingerprint) do
    me = self()

    spawn(fn ->
      if source.poll?(fingerprint),
        do: CacheManager.source_updated(source, fingerprint)

      send(me, {:poll_done, source, fingerprint})
    end)

    Process.send_after(me, {:poll_timeout, source, fingerprint}, @timeout)
  end
end
