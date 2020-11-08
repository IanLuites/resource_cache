defmodule ResourceCache.Cache do
  alias ResourceCache.{Callbacks, Compiler, Config, Utility}
  require Logger

  @spec generate(Macro.Env.t()) :: term | no_return()
  def generate(env) do
    mod = env.module

    {callbacks, _} =
      Callbacks.from_opts(
        on_configure: Module.get_attribute(mod, :cache_on_configure, []),
        pre_update: Module.get_attribute(mod, :cache_pre_update, []),
        on_update: Module.get_attribute(mod, :cache_on_update, [])
      )

    case Config.validate(%ResourceCache.Config{
           module: mod,
           type: Module.get_attribute(mod, :cache_type),
           resource: Module.get_attribute(mod, :cache_resource),
           as: Module.get_attribute(mod, :cache_resource_as),
           source: Module.get_attribute(mod, :cache_default_source),
           indices: Module.get_attribute(mod, :cache_indices, []),
           callbacks: callbacks
         }) do
      {:ok, config} ->
        Compiler.generate(config)

      {:error, err, context} ->
        d = Keyword.get(context, :description, "Failed #{inspect(err)}.")
        raise CompileError, description: "[ResourceCache] " <> d
    end
  end

  @spec type(Macro.Env.t(), module | atom, Keyword.t()) :: term
  def type(env, type, opts) do
    {e, _opts} = Keyword.pop(opts, :only)

    if matches_env?(e) do
      mod = env.module
      t = Module.get_attribute(mod, :cache_type)

      if not is_nil(t) and is_nil(e) do
        Logger.warn(
          fn ->
            "[ResourceCache] Overwriting #{inspect(t)} tot #{inspect(type)} for #{inspect(mod)}."
          end,
          module: mod,
          type: t,
          new_type: type
        )
      end

      Module.put_attribute(mod, :cache_type, type)
    end

    nil
  end

  @spec resource(Macro.Env.t(), module | atom, term, Keyword.t()) :: term
  def resource(env, resource, convert, opts) do
    {e, opts} = Keyword.pop(opts, :only)

    if matches_env?(e) do
      resource = Macro.expand(resource, env)
      opts = Enum.map(opts, fn {k, v} -> {k, Macro.expand(v, env)} end)
      mod = env.module
      r = Module.get_attribute(mod, :cache_resource)

      if is_nil(r) or not is_nil(e) do
        Module.put_attribute(mod, :cache_resource, resource)

        # Convert
        if as = Keyword.get(opts, :as) do
          type = Keyword.get(opts, :type, Utility.spec_type(as))
          as = Macro.expand(as, env)
          Module.put_attribute(mod, :cache_resource_as, as)
          Module.put_attribute(mod, :cache_resource_type, type)

          var = Macro.var(:resource, nil)
          fields = Map.keys(as.__struct__)

          convert =
            if convert do
              convert
            else
              quote do
                unquote(var)
                |> Map.from_struct()
                |> Map.take(unquote(fields))
                |> unquote(as).__struct__()
              end
            end

          quote do
            @spec __convert__(term) :: unquote(type)
            defp __convert__(unquote(var)) do
              unquote(convert)
            end
          end
        else
          type = Keyword.get(opts, :type, Utility.spec_type(resource))
          Module.put_attribute(mod, :cache_resource_type, type)

          quote do
            @spec __convert__(term) :: unquote(type)
            defp __convert__(resource), do: resource
          end
        end
      else
        Logger.warn(
          fn ->
            "[ResourceCache] Ignoring resource #{inspect(resource)} for #{inspect(mod)}, since #{
              inspect(r)
            } has already been set as resource."
          end,
          module: mod,
          resource: r,
          new: resource
        )
      end
    end
  end

  @spec source(Macro.Env.t(), module, Keyword.t()) :: term
  def source(env, source, opts) do
    source = Macro.expand(source, env)
    opts = Enum.map(opts, fn {k, v} -> {k, Macro.expand(v, env)} end)
    {e, opts} = Keyword.pop(opts, :only)

    if matches_env?(e) do
      mod = env.module

      if p = Module.get_attribute(mod, :cache_default_source) do
        Logger.warn(
          fn ->
            "[ResourceCache] Overwriting previously set source for #{inspect(mod)} from #{
              inspect(elem(p, 0))
            } to #{inspect(source)}."
          end,
          module: mod,
          source: elem(p, 0),
          new: source
        )
      end

      opts =
        case Keyword.get(opts, :interval) do
          nil -> opts
          v when is_integer(v) -> opts
          extra -> Keyword.put(opts, :interval, extra |> Code.eval_quoted([], env) |> elem(0))
        end

      Module.put_attribute(mod, :cache_default_source, {source, opts})
    end

    nil
  end

  def index(env, field, opts) do
    order_by =
      if o = Keyword.get(opts, :order_by) do
        o |> Macro.expand(env) |> callback_alias_expand(env)
      else
        &Function.identity/1
      end

    index = %ResourceCache.Config.Index{
      index: field,
      type: Keyword.get(opts, :type, :term),
      primary: Keyword.get(opts, :primary, false),
      order: order_by,
      doc: Module.delete_attribute(env.module, :doc)
    }

    Module.put_attribute(env.module, :cache_indices, index)
  end

  @spec reject(Macro.Env.t(), atom | nil, term, Keyword.t()) :: term
  def reject(env, field, code, opts)

  def reject(env, field, code, opts) do
    filter(
      env,
      field,
      quote(do: not unquote(code)),
      opts
    )
  end

  @spec filter(Macro.Env.t(), atom | nil, term, Keyword.t()) :: term
  def filter(env, field, code, opts)

  def filter(env, field, code, opts) do
    filters = Module.get_attribute(env.module, :cache_filters, [])
    id = Enum.count(filters)
    fun = :"__filter_#{id}__"

    Module.put_attribute(env.module, :cache_filters, {fun, Keyword.get(opts, :pre, false)})

    if is_nil(field) do
      quote do
        defp unquote(fun)(unquote(Macro.var(:resource, nil))) do
          unquote(code)
        end
      end
    else
      var = {:%{}, [], [{field, Macro.var(field, nil)}]}

      quote do
        defp unquote(fun)(unquote(var)) do
          unquote(code)
        end
      end
    end
  end

  @spec on_configure(Macro.Env.t(), ResourceCache.hook(), Keyword.t()) :: term
  def on_configure(env, callback, opts)

  def on_configure(env, callback, opts) do
    {e, _opts} = Keyword.pop(opts, :only)

    if matches_env?(e) do
      callback = callback |> Macro.expand(env) |> callback_alias_expand(env)

      with {_cb, []} <- Code.eval_quoted(callback, []),
           do: Module.put_attribute(env.module, :cache_on_configure, callback)

      nil
    end
  end

  @spec on_update(Macro.Env.t(), ResourceCache.hook(), Keyword.t()) :: term
  def on_update(env, callback, opts)

  def on_update(env, callback, opts) do
    {e, _opts} = Keyword.pop(opts, :only)

    if matches_env?(e) do
      callback = callback |> Macro.expand(env) |> callback_alias_expand(env)

      with {_cb, []} <- Code.eval_quoted(callback),
           do: Module.put_attribute(env.module, :cache_on_update, callback)

      nil
    end
  end

  defp callback_alias_expand(callback, env)

  defp callback_alias_expand(callback, env) do
    Macro.prewalk(callback, fn
      a = {:__aliases__, _, _} -> Macro.expand(a, env)
      code -> code
    end)
  end

  @spec optimize(Macro.Env.t(), atom | nil, term, Keyword.t()) :: term
  def optimize(env, field, code, opts)

  def optimize(env, field, code, _opts) do
    filters = Module.get_attribute(env.module, :cache_optimizers, [])
    id = Enum.count(filters)
    fun = :"__optimize_#{id}__"

    Module.put_attribute(env.module, :cache_optimizers, fun)

    if is_nil(field) do
      quote do
        defp unquote(fun)(unquote(Macro.var(:resource, nil))) do
          unquote(code)
        end
      end
    else
      resource = Macro.var(:resource, __MODULE__)
      updated = Macro.var(:updated, __MODULE__)
      var = {:%{}, [], [{field, Macro.var(field, nil)}]}
      update = {:%{}, [], [{:|, [], [resource, [{field, updated}]]}]}

      quote do
        defp unquote(fun)(unquote(resource) = unquote(var)) do
          unquote(updated) = unquote(code)
          unquote(update)
        end
      end
    end
  end

  @spec matches_env?([:prod | :dev | :test] | :prod | :dev | :test | nil) :: boolean
  defp matches_env?(env)
  defp matches_env?(nil), do: true
  defp matches_env?([]), do: false
  defp matches_env?(env) when is_atom(env), do: Utility.mix_env() == env
  defp matches_env?(envs) when is_list(envs), do: Utility.mix_env() in envs
  defp matches_env?(_), do: false
end
