defmodule ResourceCache.Source do
  @type fingerprint :: term

  @callback __type__() :: :cache | :source | :bridge
  @callback fingerprint(cache :: module, opts :: Keyword.t()) :: term
  @callback primary(fingerprint :: ResourceCache.Source.fingerprint()) :: atom | nil
  @callback init(cache :: module, fingerprint :: fingerprint(), opts :: Keyword.t()) ::
              :ok | {:error, atom}
  @callback release(cache :: module, fingerprint :: fingerprint()) ::
              :ok | {:error, atom}
  @callback list(state :: term, allow_cached? :: boolean) :: [term]

  @doc false
  @spec __using__(opts :: Keyword.t()) :: term
  defmacro __using__(opts \\ []) do
    type = Keyword.get(opts, :type, :poll)

    quote do
      @behaviour unquote(__MODULE__)

      @doc false
      @impl unquote(__MODULE__)
      @spec __type__ :: :cache | :source | :bridge
      def __type__, do: :source

      @doc false
      @spec __config__ :: %{type: :poll | :interrupt}
      def __config__, do: %{type: unquote(type)}

      @spec updated(fingerprint :: ResourceCache.Source.fingerprint()) :: :ok
      def updated(fingerprint)

      def updated(fingerprint),
        do: unquote(ResourceCache.CacheManager).source_updated(__MODULE__, fingerprint)

      @doc false
      @impl unquote(__MODULE__)
      @spec fingerprint(cache :: module, opts :: Keyword.t()) :: term
      def fingerprint(cache, opts)
      def fingerprint(cache, _opts), do: cache.__config__().resource

      @doc false
      @impl unquote(__MODULE__)
      @spec primary(fingerprint :: ResourceCache.Source.fingerprint()) :: atom | nil
      def primary(fingerprint)
      def primary(_fingerprint), do: nil

      defoverridable fingerprint: 2, primary: 1
    end
  end
end
