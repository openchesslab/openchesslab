defmodule Analysis.ApplicationTest do
  use ExUnit.Case, async: false

  alias Analysis.Application, as: AnalysisApplication
  alias Analysis.PositionStore
  alias Analysis.PositionStoreOwner

  setup do
    previous_position_store =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    previous_position_store_owner =
      Application.get_env(
        :analysis,
        PositionStoreOwner,
        :not_configured
      )

    on_exit(fn ->
      restore_config(
        PositionStore,
        previous_position_store
      )

      restore_config(
        PositionStoreOwner,
        previous_position_store_owner
      )
    end)

    Application.delete_env(
      :analysis,
      PositionStoreOwner
    )

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

  test "does not start the position store on a non-owner node" do
    Application.put_env(
      :analysis,
      PositionStoreOwner,
      owner: false
    )

    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {PositionStore, _options} -> true
               _child -> false
             end
           )
  end

  test "starts the position store registry on a non-owner node" do
    Application.put_env(
      :analysis,
      PositionStoreOwner,
      owner: false
    )

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

  defp restore_config(key, :not_configured) do
    Application.delete_env(
      :analysis,
      key
    )
  end

  defp restore_config(key, value) do
    Application.put_env(
      :analysis,
      key,
      value
    )
  end
end
