defmodule ResourceCache.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    require Logger
    Logger.error("[ResourceCache] Not ready for use.")
    {:ok, self()}
  end
end
