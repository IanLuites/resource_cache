defmodule ResourceCache.Changeset do
  alias ResourceCache.CacheManager

  @type t :: %__MODULE__{
          added: [ResourceCache.resource()],
          removed: [ResourceCache.resource()],
          unchanged: [ResourceCache.resource()],
          updated: [ResourceCache.resource()]
        }

  defstruct added: [], removed: [], unchanged: [], updated: []

  @doc ~S"""
  Generate a new changeset.
  """
  @spec generate(cache :: module, new :: [ResourceCache.resource()]) ::
          {:ok, ResourceCache.Changeset.t()}
  def generate(cache, new)

  def generate(cache, new) do
    if cache.__initialized__() do
      cache
      |> primary
      |> diff(cache.list(), new)
    else
      {:ok, %__MODULE__{added: new}}
    end
  end

  @spec all(ResourceCache.Changeset.t()) :: [ResourceCache.resource()]
  def all(changeset)

  def all(%__MODULE__{added: added, unchanged: unchanged, updated: updated}) do
    added ++ unchanged ++ updated
  end

  @spec diff(atom | nil, [ResourceCache.resource()], [ResourceCache.resource()]) ::
          {:ok, ResourceCache.Changeset.t()}
  defp diff(primary, current, new)

  defp diff(nil, current, new) do
    r =
      Enum.reduce(new, %__MODULE__{removed: current}, fn item, acc ->
        case list_pop?(acc.removed, item) do
          {true, rem} -> %{acc | removed: rem, unchanged: [item | acc.unchanged]}
          {false, _} -> %{acc | added: [item | acc.added]}
        end
      end)

    {:ok, r}
  end

  defp diff(index, current, new) do
    current = Map.new(current, &{Map.get(&1, index), &1})

    {a, r} =
      Enum.reduce(new, {current, %__MODULE__{}}, fn item, {c, acc} ->
        case Map.pop(c, Map.get(item, :index)) do
          {nil, _} -> {c, %{acc | added: [item | acc.added]}}
          {^item, left} -> {left, %{acc | unchanged: [item | acc.unchanged]}}
          {_, left} -> {left, %{acc | updated: [item | acc.updated]}}
        end
      end)

    {:ok, %{r | removed: Map.values(a)}}
  end

  @spec list_pop?([ResourceCache.resource()], [ResourceCache.resource()], [
          ResourceCache.resource()
        ]) :: {boolean, [ResourceCache.resource()]}
  defp list_pop?(list, element, acc \\ [])
  defp list_pop?([], _element, acc), do: {false, acc}
  defp list_pop?([element | t], element, acc), do: {true, acc ++ t}
  defp list_pop?([h | t], element, acc), do: list_pop?(t, element, [h | acc])

  @spec primary(cache :: module) :: atom | nil
  defp primary(cache)

  defp primary(cache) do
    with {source, fingerprint} <- CacheManager.source_fingerprint(cache),
         field when field != nil <- source.primary(fingerprint) do
      field
    else
      _ -> Enum.find_value(cache.__config__().indices, &if(&1.primary, do: &1.index))
    end
  end
end
