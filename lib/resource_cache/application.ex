defmodule ResourceCache.Application do
  @moduledoc false
  use Application

  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    children = [
      ResourceCache.Compiler,
      ResourceCache.Supervisor,
      ResourceCache.PollManager,
      ResourceCache.CallbackManager,
      ResourceCache.CacheManager
    ]

    opts = [strategy: :one_for_one, name: ResourceCache]
    Supervisor.start_link(children, opts)
  end
end
