defmodule Analysis.ApplicationTest do
  use ExUnit.Case, async: false

  alias Analysis.Application, as: AnalysisApplication
  alias Analysis.PositionStore

  setup do
    previous =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            PositionStore
          )

        value ->
          Application.put_env(
            :analysis,
            PositionStore,
            value
          )
      end
    end)

    :ok
  end

  test "starts the position store with no options by default" do
    Application.delete_env(
      :analysis,
      PositionStore
    )

    assert {
             PositionStore,
             []
           } in AnalysisApplication.children()
  end

  test "starts the position store registry" do
    assert {
             Horde.Registry,
             [
               name: Analysis.PositionStoreRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "passes configured options to the position store" do
    options = [
      directory: "positions",
      records_per_segment: 100,
      exact_bucket_count: 200,
      property_bucket_count: 300
    ]

    Application.put_env(
      :analysis,
      PositionStore,
      options
    )

    assert {
             PositionStore,
             options
           } in AnalysisApplication.children()
  end
end
