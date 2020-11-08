defmodule ResourceCache.Compilers.ETS do
  use ResourceCache.Compiler
  alias ResourceCache.CacheManager
  alias ResourceCache.Supervisor, as: ResourceSupervisor
  import ResourceCache.Utility

  @impl ResourceCache.Compiler
  @spec update(module, ResourceCache.Changeset.t()) :: :ok
  def update(cache, changeset)

  def update(cache, %ResourceCache.Changeset{added: added, removed: removed, updated: updated}) do
    mod = Module.concat(cache, :__Cache__)

    mod.__init__
    primary = mod.__primary__

    insert =
      if p = Enum.find(cache.__config__().indices, &(&1.index == primary)),
        do: Enum.sort_by(added ++ updated, sort_by(p.order, p.index)) |> :lists.reverse(),
        else: added ++ updated

    Enum.each(insert, &:ets.insert(mod, entry(primary, &1)))
    Enum.each(removed, &:ets.delete(mod, entry(primary, &1)))

    :ok
  end

  @spec entry(atom | nil, map) :: tuple
  defp entry(primary, item)
  defp entry(nil, item), do: {item}
  defp entry(primary, item), do: {Map.get(item, primary), item}

  @impl ResourceCache.Compiler
  @spec generate(ResourceCache.Config.t()) :: term
  def generate(config)

  def generate(config = %ResourceCache.Config{indices: indices}) do
    primary = Enum.find(indices, & &1.primary)
    index = if primary, do: 1, else: 0

    primary_get =
      if primary do
        quote do
          unquote(decorate_get(config, primary, :get))

          def get(id) do
            case :ets.lookup(__MODULE__, id) do
              [] -> nil
              [{_, v}] -> v
            end
          rescue
            _ ->
              __init__()
              get(id)
          end
        end
      end

    get =
      Enum.reduce(indices, nil, fn
        index, acc ->
          func = :"get_by_#{index.index}"

          impl =
            cond do
              index.primary ->
                quote do
                  def unquote(func)(value), do: get(value)
                end

              is_nil(primary) ->
                quote do
                  def unquote(func)(value) do
                    with {v} <-
                           __MODULE__
                           |> :ets.select([
                             {{%{unquote(index.index) => :"$1"}}, [{:==, :"$1", value}], [:"$_"]}
                           ])
                           |> List.first(),
                         do: v
                  rescue
                    _ ->
                      __init__()
                      unquote(func)(value)
                  end
                end

              :with_index ->
                quote do
                  def unquote(func)(value) do
                    with {_, v} <-
                           __MODULE__
                           |> :ets.select([
                             {{:_, %{unquote(index.index) => :"$1"}}, [{:==, :"$1", value}],
                              [:"$_"]}
                           ])
                           |> List.first(),
                         do: v
                  rescue
                    _ ->
                      __init__()
                      unquote(func)(value)
                  end
                end
            end

          quote do
            unquote(acc)

            unquote(decorate_get(config, index))
            unquote(impl)
          end
      end)

    preload =
      if config.source do
        {s, o} = config.source

        quote do
          me = self()
          ref = make_ref()

          callback = fn ->
            send(me, {:preloaded, ref})
            :unhook
          end

          opts = Keyword.put(unquote(o), :on_update, callback)

          unquote(CacheManager).preload(unquote(config.module), unquote(s), opts)

          receive do
            {:preloaded, ^ref} -> :ok
          end
        end
      end

    quote do
      unquote(primary_get)
      unquote(get)

      @doc false
      @spec __init__(boolean) :: :ok
      def __init__(preload \\ true)

      def __init__(preload) do
        if :ets.whereis(__MODULE__) == :undefined do
          __MODULE__
          |> :ets.new([
            :public,
            :named_table,
            :set,
            read_concurrency: true
          ])
          |> unquote(ResourceSupervisor).give_away()

          if preload, do: unquote(preload)
        end

        :ok
      rescue
        _ -> :ok
      end

      @doc false
      @spec __primary__ :: atom
      def __primary__, do: unquote(if primary, do: primary.index)

      unquote(spec(:list, [], spec_list(spec_type(config.resource)), nil))

      @doc unquote(list_doc(config))
      def list do
        __MODULE__
        |> :ets.tab2list()
        |> Enum.map(&elem(&1, unquote(index)))
      rescue
        _ ->
          __init__()
          list()
      end
    end
  end
end
