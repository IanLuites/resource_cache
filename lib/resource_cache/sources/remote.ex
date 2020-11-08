# defmodule ResourceCache.Sources.Remote do
#   use ResourceCache.Source, type: :interrupt

#   @impl ResourceCache.Source
#   def init(resource) do
#     :ets.create(resource, [:public])

#     {:ok, ref, [%{
#       id: ref,

#     }]}
#   end

#   @impl ResourceCache.Source
#   def list(ref, resource) do
#     :ets.tab2list(resource)
#   end

#   def insert(resource, value) do

#   end

#   def clear(resource)
# end
