defmodule ResourceCache do
  @moduledoc ~S"""
  Fast caching with clear syntax.

  ## Quick Setup

  ```elixir
  def deps do
    [
      {:resource_cache, "~> 0.1"}
    ]
  end
  ```

  Define a cache by setting a resource (in this case Ecto schema)
  and source. (The Ecto repo to query.)
  ```elixir
  defmodule MyApp.Categories do
    use ResourceCache
    resource MyApp.Category
    source :ecto, repo: MyApp.Repo
  end
  ```

  Now the cache can be used for fast listing:
  ```elixir
  iex> MyApp.Categories.list()
  [%MyApp.Category{}, ...]
  ```

  Indices can be added to do quick lookups by value:
  ```elixir
  defmodule MyApp.Categories do
    use ResourceCache
    resource MyApp.Category
    source :ecto, repo: MyApp.Repo

    index :slug, primary: true
  end
  ```

  Now `get_by_slug/1` can be used.
  In addition to the standard `get_by_slug`,
  `get/1` is also available since it was defined as primary index.

  ```elixir
  iex> MyApp.Categories.get("electronics")
  %MyApp.Category{}
  iex> MyApp.Categories.get_by_slug("electronics")
  %MyApp.Category{}
  iex> MyApp.Categories.get("fake")
  nil
  iex> MyApp.Categories.get_by_slug("fake")
  nil
  ```

  There is no limit to the amount of indices that can be added.

  It is possible to pass an optional type for each index,
  to generate cleaner specs for the function arguments.

  ```elixir
  index :slug, primary: true, type: String.t
  ```
  """
end
