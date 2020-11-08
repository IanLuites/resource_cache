defmodule ResourceCache.Compilers.Hardcoded do
  use ResourceCache.Compiler
  alias ResourceCache.{CacheManager, Changeset}
  import ResourceCache.Utility, only: [sort_by: 2]

  @impl ResourceCache.Compiler
  @spec update(module, ResourceCache.Changeset.t()) :: :ok
  def update(cache, changeset) do
    data = Changeset.all(changeset)
    mod = Module.concat(cache, :__Cache__)

    :code.purge(mod)
    :code.delete(mod)

    Code.compiler_options(ignore_module_conflict: true)

    Code.compile_quoted(
      quote do
        defmodule unquote(mod) do
          @moduledoc false
          unquote(generate(cache.__config__, data))
        end
      end
    )

    Code.compiler_options(ignore_module_conflict: false)

    :ok
  end

  @impl ResourceCache.Compiler
  @spec generate(ResourceCache.Config.t()) :: term
  def generate(config)

  def generate(%ResourceCache.Config{module: cache, indices: indices}) do
    primary = Enum.find(indices, & &1.primary)

    primary_get =
      if primary do
        quote do
          def get(value),
            do: Enum.find_value(list(), &(Map.get(&1, unquote(primary.index)) == value))
        end
      end

    get =
      Enum.reduce(indices, primary_get, fn
        index, acc ->
          func = :"get_by_#{index.index}"

          quote do
            unquote(acc)

            def unquote(func)(value),
              do: Enum.find_value(list(), &(Map.get(&1, unquote(index.index)) == value))
          end
      end)

    quote do
      unquote(get)

      def list do
        if s = unquote(cache).__config__().source do
          {source, source_opts} = s

          if fingerprint = unquote(CacheManager).fingerprint(unquote(cache)) do
            source.list(fingerprint, true)
          else
            me = self()
            ref = make_ref()

            callback = fn _cache, data ->
              send(me, {:pre_update, ref, data})
              :unhook
            end

            opts = Keyword.put(source_opts, :pre_update, callback)

            unquote(CacheManager).preload(unquote(cache), source, opts)

            receive do
              {:pre_update, ^ref, data} -> data
            end
          end
        else
          Enum.random([[]])
        end
      end
    end
  end

  @spec generate(ResourceCache.Config.t(), [map]) :: term
  def generate(config, data)

  def generate(%ResourceCache.Config{indices: indices}, data) do
    primary = Enum.find(indices, & &1.primary)
    primary_get = if primary, do: getter(:get, primary, data)

    get =
      Enum.reduce(indices, primary_get, fn
        index, acc ->
          func = :"get_by_#{index.index}"

          impl =
            if index.primary do
              quote do
                def unquote(func)(value), do: get(value)
              end
            else
              getter(func, index, data)
            end

          quote do
            unquote(acc)
            unquote(impl)
          end
      end)

    quote do
      unquote(get)

      def list, do: unquote(Macro.escape(data))
    end
  end

  @spec getter(atom, ResourceCache.Config.Index.t(), [map]) :: term
  defp getter(func, index, data)

  defp getter(func, %ResourceCache.Config.Index{index: field, order: order}, data) do
    g =
      data
      |> Enum.sort_by(sort_by(order, field))
      |> Enum.reduce(nil, fn entry, acc ->
        quote do
          unquote(acc)

          def unquote(func)(unquote(Macro.escape(Map.get(entry, field)))),
            do: unquote(Macro.escape(entry))
        end
      end)

    quote do
      def unquote(func)(unquote(Macro.var(field, nil)))
      unquote(g)
      def unquote(func)(_), do: nil
    end
  end
end
