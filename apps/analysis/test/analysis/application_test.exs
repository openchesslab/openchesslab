defmodule Analysis.ApplicationTest do
  use ExUnit.Case, async: false

  alias Analysis.Application, as: AnalysisApplication
  alias Analysis.GameStore
  alias Analysis.GameStoreOwner
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

    previous_game_store_owner =
      Application.get_env(
        :analysis,
        GameStoreOwner,
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

      restore_config(
        GameStoreOwner,
        previous_game_store_owner
      )
    end)

    Application.delete_env(
      :analysis,
      PositionStoreOwner
    )

    Application.delete_env(
      :analysis,
      GameStoreOwner
    )

    :ok
  end

  test "starts the position store with the cluster-wide server by default" do
    Application.delete_env(
      :analysis,
      PositionStore
    )

    assert {
             PositionStore,
             [
               server: PositionStore.clustered_server()
             ]
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
             Keyword.put(
               options,
               :server,
               PositionStore.clustered_server()
             )
           } in AnalysisApplication.children()
  end

  test "preserves an explicitly configured position store server" do
    options = [
      server: :custom_position_store
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

  test "starts DNS clustering disabled by default" do
    previous =
      Application.get_env(
        :analysis,
        :dns_cluster_query,
        :not_configured
      )

    on_exit(fn ->
      restore_config(
        :dns_cluster_query,
        previous
      )
    end)

    Application.delete_env(
      :analysis,
      :dns_cluster_query
    )

    assert {
             DNSCluster,
             [
               query: :ignore
             ]
           } in AnalysisApplication.children()
  end

  test "passes the configured DNS cluster query" do
    previous =
      Application.get_env(
        :analysis,
        :dns_cluster_query,
        :not_configured
      )

    on_exit(fn ->
      restore_config(
        :dns_cluster_query,
        previous
      )
    end)

    Application.put_env(
      :analysis,
      :dns_cluster_query,
      "openchesslab.internal"
    )

    assert {
             DNSCluster,
             [
               query: "openchesslab.internal"
             ]
           } in AnalysisApplication.children()
  end

  test "starts the game store registry" do
    assert {
             Horde.Registry,
             [
               name: Analysis.GameStoreRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "starts the game store with the cluster-wide store by default" do
    assert {
             Analysis.GameStore.Memory,
             [
               name: GameStore.clustered_store()
             ]
           } in AnalysisApplication.children()
  end

  test "does not start the game store on a non-owner node" do
    Application.put_env(
      :analysis,
      GameStoreOwner,
      owner: false
    )

    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {Analysis.GameStore.Memory, _options} -> true
               _child -> false
             end
           )
  end

  test "starts the game store registry on a non-owner node" do
    Application.put_env(
      :analysis,
      GameStoreOwner,
      owner: false
    )

    assert {
             Horde.Registry,
             [
               name: Analysis.GameStoreRegistry,
               keys: :unique,
               members: :auto
             ]
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
