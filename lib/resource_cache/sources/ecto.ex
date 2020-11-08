defmodule ResourceCache.Sources.Ecto do
  use ResourceCache.Source, type: :poll
  alias ResourceCache.Supervisor, as: ResourceSupervisor

  @cache :resource_cache_ecto

  @typep fingerprint ::
           {schema :: module, repo :: module, preload :: term, timestamp :: :atom | false}

  @impl ResourceCache.Source
  def fingerprint(cache, opts)

  def fingerprint(cache, opts) do
    schema = cache.__config__().resource
    preload = Keyword.get_lazy(opts, :preload, fn -> preloads(schema) end)
    timestamp = if preload == [], do: update_timestamp(schema)

    {schema, opts[:repo], preload, timestamp || false}
  end

  @impl ResourceCache.Source
  def init(cache, fingerprint, opts)

  def init(_cache, fingerprint = {resource, repo, _preload, timestamp}, _opts) do
    with :undefined <- :ets.whereis(@cache) do
      @cache
      |> :ets.new([
        :public,
        :named_table,
        :set,
        write_concurrency: true,
        read_concurrency: true
      ])
      |> ResourceSupervisor.give_away()
    end

    ls = fetch(fingerprint)

    if timestamp do
      :ets.insert(@cache, {fingerprint, last_update(resource, repo, timestamp), ls})
    else
      :ets.insert(@cache, {fingerprint, ls})
    end

    :ok
  end

  @impl ResourceCache.Source
  def release(cache, fingerprint)
  def release(_cache, _fingerprint), do: :ok

  def poll?(fingerprint)

  def poll?(fingerprint = {_, _, _, false}) do
    ls = fetch(fingerprint)
    current = list(fingerprint, true)

    if list_equals?(ls, current) do
      false
    else
      :ets.insert(@cache, {fingerprint, ls})
      true
    end
  end

  def poll?(fingerprint = {resource, repo, _preload, timestamp}) do
    ts = last_update(resource, repo, timestamp)

    case :ets.lookup(@cache, fingerprint) do
      [{_, ^ts, _}] ->
        false

      _ ->
        :ets.insert(@cache, {fingerprint, ts, fetch(fingerprint)})
        true
    end
  end

  @impl ResourceCache.Source
  @spec list(fingerprint, boolean) :: [map]
  def list(fingerprint, allow_cached?)
  def list(fingerprint, false), do: fetch(fingerprint)

  def list(fingerprint, true) do
    case :ets.lookup(@cache, fingerprint) do
      [{_, l}] -> l
      [{_, _ts, l}] -> l
      _ -> []
    end
  end

  @spec fetch(fingerprint) :: [map]
  defp fetch(fingerprint)
  defp fetch({resource, repo, [], _timestamp}), do: repo.all(resource)

  defp fetch({resource, repo, preload, _timestamp}) do
    source = {resource.__schema__(:source), resource}
    from = apply(Ecto.Query.FromExpr, :__struct__, [[source: source]])
    query = apply(Ecto.Query, :__struct__, [[from: from, preloads: [preload]]])
    repo.all(query)
  end

  @spec preloads(module, [atom]) :: list
  defp preloads(schema, ignore \\ []) do
    x = [:__meta__, :__struct__ | schema.__schema__(:fields)]

    schema.__struct__
    |> Map.keys()
    |> Enum.reject(&(&1 in x))
    |> Enum.map(&schema.__schema__(:association, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn %{relationship: r, queryable: q} -> r == :child and q not in ignore end)
    |> Enum.map(fn %{field: f, queryable: q} ->
      case preloads(q, [schema | ignore]) do
        [] -> f
        nested -> {f, nested}
      end
    end)
  end

  @spec list_equals?([map], [map]) :: boolean
  defp list_equals?(a, b)
  defp list_equals?([], []), do: true
  defp list_equals?([], _), do: false
  defp list_equals?(_, []), do: false

  defp list_equals?([h | t], b) do
    case list_pop?(b, h) do
      {false, _} -> false
      {true, new_b} -> list_equals?(t, new_b)
    end
  end

  @spec list_pop?([map], map, [map]) :: {boolean, [map]}
  defp list_pop?(list, element, acc \\ [])
  defp list_pop?([], _element, acc), do: {false, acc}
  defp list_pop?([element | t], element, acc), do: {true, acc ++ t}
  defp list_pop?([h | t], element, acc), do: list_pop?(t, element, [h | acc])

  @spec last_update(module, module, atom) :: term
  defp last_update(resource, repo, timestamp) do
    source = {resource.__schema__(:source), resource}
    from = apply(Ecto.Query.FromExpr, :__struct__, [[source: source]])

    select =
      apply(Ecto.Query.SelectExpr, :__struct__, [
        [expr: {:max, [], [{{:., [], [{:&, [], [0]}, timestamp]}, [], []}]}]
      ])

    query = apply(Ecto.Query, :__struct__, [[from: from, select: select]])

    repo.one(query)
  end

  @spec update_timestamp(module) :: atom | nil
  defp update_timestamp(resource) do
    :autoupdate
    |> resource.__schema__()
    |> Enum.find_value(nil, fn
      {[field], {Ecto.Schema, :__timestamps__, _}} -> field
      _ -> nil
    end)
  end
end
