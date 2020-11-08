defmodule ResourceCache.Sources.Cache do
  use ResourceCache.Source, type: :interrupt

  @impl ResourceCache.Source
  def fingerprint(cache, opts)
  def fingerprint(_cache, opts), do: opts[:cache]

  @impl ResourceCache.Source
  def init(cache, fingerprint, opts)

  def init(_cache, fingerprint, _opts),
    do: fingerprint.configure(on_update: &__MODULE__.updated/1)

  @impl ResourceCache.Source
  def release(cache, fingerprint)
  def release(_cache, _fingerprint), do: :ok

  @impl ResourceCache.Source
  def list(fingerprint, allow_cached?)
  def list(fingerprint, _allow_cached?), do: fingerprint.list()
end
