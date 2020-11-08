defmodule ResourceCache.Supervisor do
  defmodule ETS do
    @moduledoc false
    use GenServer

    @doc false
    @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
    def start_link(opts \\ [])

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl GenServer
    @spec init(any) :: {:ok, nil, :hibernate}
    def init(opts)
    def init(_), do: {:ok, nil, :hibernate}

    @impl GenServer
    def handle_info(msg, state)

    def handle_info(_msg, state) do
      {:noreply, state, :hibernate}
    end
  end

  @spec give_away(atom | :ets.tid()) :: :ok
  def give_away(table) do
    :ets.give_away(table, Process.whereis(ETS), [])
    :ok
  end

  use DynamicSupervisor

  def start_link(opts \\ [])

  def start_link(opts) do
    with {:ok, pid} <- DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__) do
      DynamicSupervisor.start_child(pid, ETS)
      {:ok, pid}
    end
  end

  @impl DynamicSupervisor
  def init(opts)

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
