defmodule ResourceCache.Sources.ETS do
  use ResourceCache.Source, type: :interrupt
  alias ResourceCache.Supervisor, as: ResourceSupervisor

  @impl ResourceCache.Source
  def fingerprint(cache, opts)

  def fingerprint(cache, _opts) do
    :"ets_source_#{cache.__config__().resource}"
  end

  @impl ResourceCache.Source
  def init(cache, fingerprint, opts)

  def init(_cache, fingerprint, _opts) do
    with :undefined <- :ets.whereis(fingerprint) do
      fingerprint
      |> :ets.new([
        :public,
        :named_table,
        :set,
        write_concurrency: true,
        read_concurrency: true
      ])
      |> ResourceSupervisor.give_away()
    end

    :ok
  end

  @impl ResourceCache.Source
  def release(cache, fingerprint)

  def release(_cache, fingerprint) do
    :ets.delete(fingerprint)

    :ok
  end

  @impl ResourceCache.Source
  def list(fingerprint, allow_cached?)

  def list(fingerprint, _allow_cached?) do
    fingerprint |> :ets.tab2list() |> Enum.map(&elem(&1, 1))
  end

  def insert(cache, id, resource) do
    fingerprint = fingerprint(cache, [])
    :ets.insert(fingerprint, {id, resource})
    updated(fingerprint)

    :ok
  end

  def clear(cache)

  def clear(cache) do
    fingerprint = fingerprint(cache, [])
    :ets.delete_all_objects(fingerprint)
    updated(fingerprint)

    :ok
  end
end
