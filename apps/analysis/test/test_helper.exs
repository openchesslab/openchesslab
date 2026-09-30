exclude =
  case System.get_env("POSTGRES_TESTS") do
    "true" ->
      []

    _other ->
      [
        postgres: true
      ]
  end

ExUnit.start(exclude: exclude)
