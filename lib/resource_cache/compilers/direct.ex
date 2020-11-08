defmodule ResourceCache.Compilers.Direct do
  use ResourceCache.Compiler
  alias ResourceCache.CacheManager
  import ResourceCache.Utility

  @impl ResourceCache.Compiler
  @spec update(module, ResourceCache.Changeset.t()) :: :ok
  def update(cache, changeset)
  def update(_, _), do: :ok

  @impl ResourceCache.Compiler
  @spec generate(ResourceCache.Config.t()) :: term
  def generate(config)

  def generate(config = %ResourceCache.Config{module: cache, indices: indices}) do
    primary = Enum.find(indices, & &1.primary)

    primary_get =
      if primary do
        quote do
          unquote(decorate_get(config, primary, :get))

          def get(value), do: Enum.find(list(), &(Map.get(&1, unquote(primary.index)) == value))
        end
      end

    get =
      Enum.reduce(indices, primary_get, fn
        index, acc ->
          func = :"get_by_#{index.index}"

          quote do
            unquote(acc)

            unquote(decorate_get(config, primary))

            def unquote(func)(value),
              do: Enum.find(list(), &(Map.get(&1, unquote(index.index)) == value))
          end
      end)

    quote do
      unquote(get)

      unquote(spec(:list, [], spec_list(spec_type(config.resource)), nil))
      @doc unquote(list_doc(config))
      def list do
        if s = unquote(cache).__config__().source do
          {source, opts} = s
          fingerprint = unquote(CacheManager).fingerprint(unquote(cache))

          fp =
            if fingerprint do
              fingerprint
            else
              me = self()
              ref = make_ref()

              callback = fn ->
                send(me, {:loaded, ref})
                :unhook
              end

              opts = Keyword.put(opts, :callback, callback)

              unquote(CacheManager).preload(unquote(cache), source, opts)

              receive do
                {:loaded, ^ref} -> unquote(CacheManager).fingerprint(unquote(cache))
              end
            end

          fp
          |> source.list(false)
          |> unquote(cache).__process__()
        else
          Enum.random([[]])
        end
      end
    end
  end
end
