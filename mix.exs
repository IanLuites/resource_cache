defmodule ResourceCache.MixProject do
  use Mix.Project

  @version "0.0.1-rc0"

  def project do
    [
      app: :resource_cache,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Fast caching with clear syntax.",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [ignore_warnings: ".dialyzer", plt_add_deps: true, plt_add_apps: []],

      # Docs
      name: "Resource Cache",
      source_url: "https://github.com/IanLuites/resource_cache",
      homepage_url: "https://github.com/IanLuites/resource_cache",
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_ref: "v#{@version}",
        source_url: "https://github.com/IanLuites/resource_cache"
      ]
    ]
  end

  def package do
    [
      name: :resource_cache,
      maintainers: ["Ian Luites"],
      licenses: ["MIT"],
      files: [
        # Elixir
        "lib/resource_cache",
        "lib/resource_cache.ex",
        ".formatter.exs",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      links: %{
        "GitHub" => "https://github.com/IanLuites/resource_cache"
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ResourceCache.Application, []}
    ]
  end

  defp deps do
    [
      {:heimdallr, ">= 0.0.0", only: [:dev]},
      {:ex_doc, ">= 0.0.0", only: [:dev]}
    ]
  end
end
