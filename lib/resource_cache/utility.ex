defmodule ResourceCache.Utility do
  alias ResourceCache.Config

  ### Decorators ###

  @spec decorate_get(ResourceCache.Config.t(), ResourceCache.Config.Index.t()) :: term
  def decorate_get(config, index), do: decorate_get(config, index, :"get_by_#{index.index}")

  @spec decorate_get(ResourceCache.Config.t(), ResourceCache.Config.Index.t(), atom) :: term
  def decorate_get(config, index, name)

  def decorate_get(config, index = %{index: field, type: type}, name) do
    f = {field, type}
    resource = Config.resource(config)

    quote do
      @doc unquote(get_doc(config, index, name))
      unquote(spec(name, [f], spec_or(spec_type(resource), nil)))
      def unquote(name)(unquote(Macro.var(field, nil)))
    end
  end

  @spec decorate_get_by(ResourceCache.Config.t()) :: term
  def decorate_get_by(config) do
    resource = Config.resource(config)

    quote do
      @doc unquote(get_by_doc(config))
      unquote(spec(:get_by, [:term], spec_or(spec_type(resource), nil)))
      def get_by(lookup)
    end
  end

  ### Specs ###
  @spec spec_list(term) :: term
  def spec_list(type)
  def spec_list(type), do: [type]

  @spec spec_or(term, term) :: term
  def spec_or(a, b)
  def spec_or(a, b), do: {:|, [], [a, b]}

  @spec spec_type(module, atom) :: term
  def spec_type(module, type \\ :t)

  def spec_type(module, type) do
    {{:., [], [{:__aliases__, [alias: false], [module]}, type]}, [], []}
  end

  @spec spec(atom, [atom | {atom, term}], term, module) :: term
  def spec(func, args, result, scope \\ Elixir)

  def spec(func, [], result, scope) do
    {:@, [context: scope, import: Kernel],
     [
       {:spec, [context: scope],
        [
          {:"::", [], [{func, [], scope}, result]}
        ]}
     ]}
  end

  def spec(func, args, result, scope) do
    argv =
      Enum.map(args, fn
        {name, type} -> {:"::", [], [{name, [], scope}, type]}
        name -> {:"::", [], [{name, [], scope}, {:term, [], scope}]}
      end)

    {:@, [context: scope, import: Kernel],
     [
       {:spec, [context: scope],
        [
          {:"::", [], [{func, [], argv}, result]}
        ]}
     ]}
  end

  ### Docs ###

  @spec get_doc(ResourceCache.Config.t(), ResourceCache.Config.Index.t(), atom) :: String.t()
  def get_doc(config, index, func)

  def get_doc(config, %{doc: doc, index: index}, func) do
    resource = Config.resource(config)

    name =
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.replace("_", " ")

    """
    #{doc || "Lookup a #{name} by #{index}."}

    ## Example

    ```elixir
    iex> #{func}(...)
    %#{inspect(resource)}{...}
    ```
    ```elixir
    iex> #{func}(...)
    nil
    ```
    """
  end

  @spec get_by_doc(ResourceCache.Config.t()) :: String.t()
  def get_by_doc(config)

  def get_by_doc(config) do
    resource = Config.resource(config)

    name =
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.replace("_", " ")

    lookups =
      Enum.reduce(config.indices, "", fn %{index: f}, acc ->
        acc <>
          """
          iex> get_by(#{f}: .....)
          %#{inspect(resource)}{...}
          """
      end)

    """
    Lookup a #{name} by dynamic index lookup.

    ## Example

    ```elixir
    #{lookups}
    ```
    ```elixir
    iex> get_by(fake: "wrong")
    nil
    ```
    """
  end

  @spec list_doc(ResourceCache.Config.t()) :: String.t()
  def list_doc(config)

  def list_doc(config) do
    resource = Config.resource(config)

    name =
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.replace("_", " ")

    """
    List all #{name}.

    ## Example

    ```elixir
    iex> list()
    [%#{inspect(resource)}{}, ...]
    ```
    """
  end

  ### Env Detection ###

  main_project =
    if p = Process.whereis(Mix.TasksServer) do
      module =
        p
        |> Agent.get(&Map.keys/1)
        |> Enum.find_value(false, fn
          {:task, task, m} when task in ~W(app.start deps.loadpaths) -> m
          _ -> false
        end)

      if module, do: module.project()
    end

  env =
    cond do
      e = System.get_env("MIX_ENV") ->
        String.to_existing_atom(e)

      p = Process.whereis(Mix.TasksServer) ->
        tasks =
          p
          |> Agent.get(&Map.keys(&1))
          |> Enum.map(&elem(&1, 1))
          |> Enum.uniq()

        preferred =
          if main_project, do: Keyword.get(main_project, :preferred_cli_env, []), else: []

        cond do
          env = Enum.find_value(tasks, &Mix.Task.preferred_cli_env/1) -> env
          env = Enum.find_value(tasks, &Keyword.get(preferred, String.to_atom(&1))) -> env
          :default -> :dev
        end

      :default ->
        :prod
    end

  @doc ~S"""
  Get the current Mix environment.

  ## Example

  ```elixir
  iex> ApplicationX.mix_env
  :test
  ```
  """
  @spec mix_env :: atom
  def mix_env, do: unquote(env)

  @doc ~S"""
  Generate a sort_by function based on the given sorter.

  Mostly sanitizes quoted functions from compile time.
  """
  @spec sort_by(sorter :: term, field :: atom) :: fun()
  def sort_by(sorter, field)

  def sort_by(sorter, field) when is_function(sorter) do
    if sorter == (&Function.identity/1),
      do: &Map.get(&1, field),
      else: &sorter.(Map.get(&1, field))
  end

  def sort_by(sorter, field) do
    case Code.eval_quoted(sorter) do
      {fun, []} -> sort_by(fun, field)
      _ -> &Map.get(&1, field)
    end
  end
end
