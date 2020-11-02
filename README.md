# Resource Cache

[![Hex.pm](https://img.shields.io/hexpm/v/resource_cache.svg "Hex")](https://hex.pm/packages/resource_cache)
[![Build Status](https://travis-ci.org/IanLuites/resource_cache.svg?branch=master)](https://travis-ci.org/IanLuites/resource_cache)
[![Coverage Status](https://coveralls.io/repos/github/IanLuites/resource_cache/badge.svg?branch=master)](https://coveralls.io/github/IanLuites/resource_cache?branch=master)
[![Hex.pm](https://img.shields.io/hexpm/l/resource_cache.svg "License")](LICENSE)

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

## Roadmap

### To 0.1.0

- Cleanup code for publishing
- Mechanism for caches that depend on caches configured with `type: :direct`
- HTTP bridge improved polling logic

### Future

- TCP bridge

## License

MIT License

Copyright (c) 2020 Ian Luites

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
