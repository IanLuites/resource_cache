locals_without_parens = [
  filter: 1,
  filter: 2,
  filter: 3,
  index: 1,
  index: 2,
  optimize: 1,
  optimize: 2,
  optimize: 3,
  query: 2,
  reject: 1,
  reject: 2,
  reject: 3,
  resource: 1,
  resource: 2,
  resource: 3,
  source: 1,
  source: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  # import_deps: [],
  export: [
    locals_without_parens: locals_without_parens
  ]
]
