# Used by "mix format"
[
  import_deps: [:ecto],
  inputs: ["{mix,.formatter}.exs", "{benchmarks,config,lib,test}/**/*.{ex,exs}"],
  plugins: [Quokka],
  subdirectories: ["priv/*/migrations"]
]
