defmodule Analysis.ApplicationTest do
  use ExUnit.Case, async: false

  alias Analysis.AnalysisStore
  alias Analysis.AnalysisStore.Dets
  alias Analysis.AnalysisStore.Memory
  alias Analysis.AnalysisStoreOwner
  alias Analysis.Application, as: AnalysisApplication
  alias Analysis.GameRecordStore
  alias Analysis.GameRecordStoreOwner
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

    previous_analysis_store_owner =
      Application.get_env(
        :analysis,
        AnalysisStoreOwner,
        :not_configured
      )

    previous_analysis_store =
      Application.get_env(
        :analysis,
        AnalysisStore,
        :not_configured
      )

    previous_game_store =
      Application.get_env(
        :analysis,
        GameStore,
        :not_configured
      )

    previous_game_store_owner =
      Application.get_env(
        :analysis,
        GameStoreOwner,
        :not_configured
      )

    previous_game_record_store_owner =
      Application.get_env(
        :analysis,
        GameRecordStoreOwner,
        :not_configured
      )

    previous_game_record_store =
      Application.get_env(
        :analysis,
        GameRecordStore,
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
        AnalysisStoreOwner,
        previous_analysis_store_owner
      )

      restore_config(
        AnalysisStore,
        previous_analysis_store
      )

      restore_config(
        GameStore,
        previous_game_store
      )

      restore_config(
        GameStoreOwner,
        previous_game_store_owner
      )

      restore_config(
        GameRecordStoreOwner,
        previous_game_record_store_owner
      )

      restore_config(
        GameRecordStore,
        previous_game_record_store
      )
    end)

    Application.delete_env(
      :analysis,
      PositionStoreOwner
    )

    Application.delete_env(
      :analysis,
      AnalysisStoreOwner
    )

    Application.delete_env(
      :analysis,
      AnalysisStore
    )

    Application.delete_env(
      :analysis,
      GameStore
    )

    Application.delete_env(
      :analysis,
      GameStoreOwner
    )

    Application.delete_env(
      :analysis,
      GameRecordStore
    )

    Application.delete_env(
      :analysis,
      GameRecordStoreOwner
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

  test "starts the configured analysis store adapter" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      adapter: Dets,
      path: "analyses.dets"
    )

    assert {
             Dets,
             options
           } =
             Enum.find(
               AnalysisApplication.children(),
               fn
                 {Dets, _options} -> true
                 _child -> false
               end
             )

    assert Keyword.get(options, :path) == "analyses.dets"

    assert Keyword.get(options, :name) ==
             AnalysisStore.clustered_store()
  end

  test "does not start the configured analysis store adapter on a non-owner node" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      adapter: Dets,
      path: "analyses.dets"
    )

    Application.put_env(
      :analysis,
      AnalysisStoreOwner,
      owner: false
    )

    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {Dets, _options} -> true
               _child -> false
             end
           )
  end

  test "preserves an explicitly configured analysis store" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      adapter: Dets,
      path: "analyses.dets",
      store: :custom_analysis_store
    )

    assert {
             Dets,
             options
           } =
             Enum.find(
               AnalysisApplication.children(),
               fn
                 {Dets, _options} -> true
                 _child -> false
               end
             )

    assert Keyword.get(options, :path) == "analyses.dets"
    assert Keyword.get(options, :name) == :custom_analysis_store
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

  test "starts the analysis store registry" do
    assert {
             Horde.Registry,
             [
               name: Analysis.AnalysisStoreRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "starts the analysis store with the cluster-wide store by default" do
    assert {
             Memory,
             [
               name: AnalysisStore.clustered_store()
             ]
           } in AnalysisApplication.children()
  end

  test "does not start the analysis store on a non-owner node" do
    Application.put_env(
      :analysis,
      AnalysisStoreOwner,
      owner: false
    )

    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {Memory, _options} -> true
               _child -> false
             end
           )
  end

  test "starts the analysis store registry on a non-owner node" do
    Application.put_env(
      :analysis,
      AnalysisStoreOwner,
      owner: false
    )

    assert {
             Horde.Registry,
             [
               name: Analysis.AnalysisStoreRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "starts the canonical game store registry" do
    assert {
             Horde.Registry,
             [
               name: Analysis.GameStoreRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "starts the canonical game store with the cluster-wide server by default" do
    assert {
             GameStore,
             [
               server: GameStore.clustered_server()
             ]
           } in AnalysisApplication.children()
  end

  test "does not start the canonical game store on a non-owner node" do
    Application.put_env(
      :analysis,
      GameStoreOwner,
      owner: false
    )

    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {GameStore, _options} ->
                 true

               _child ->
                 false
             end
           )
  end

  test "starts the canonical game store registry on a non-owner node" do
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

  test "passes configured options to the canonical game store" do
    options = [
      directory: "games",
      bucket_count: 200,
      position_bucket_count: 300
    ]

    Application.put_env(
      :analysis,
      GameStore,
      options
    )

    assert {
             GameStore,
             Keyword.put(
               options,
               :server,
               GameStore.clustered_server()
             )
           } in AnalysisApplication.children()
  end

  test "preserves an explicitly configured canonical game store server" do
    options = [
      server: :custom_game_store
    ]

    Application.put_env(
      :analysis,
      GameStore,
      options
    )

    assert {
             GameStore,
             options
           } in AnalysisApplication.children()
  end

  test "starts the game record store registry" do
    assert {
             Horde.Registry,
             [
               name: Analysis.GameRecordStoreRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "starts the game record store with the cluster-wide store by default" do
    assert {
             Analysis.GameRecordStore.Memory,
             [
               name: GameRecordStore.clustered_store()
             ]
           } in AnalysisApplication.children()
  end

  test "does not start the game record store on a non-owner node" do
    Application.put_env(
      :analysis,
      GameRecordStoreOwner,
      owner: false
    )

    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {
                 Analysis.GameRecordStore.Memory,
                 _options
               } ->
                 true

               _child ->
                 false
             end
           )
  end

  test "starts the game record store registry on a non-owner node" do
    Application.put_env(
      :analysis,
      GameRecordStoreOwner,
      owner: false
    )

    assert {
             Horde.Registry,
             [
               name: Analysis.GameRecordStoreRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "does not start a position store process for a repository-backed store" do
    Application.put_env(
      :analysis,
      PositionStore,
      repository: Analysis.PositionRepository.Postgres
    )

    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {PositionStore, _options} ->
                 true

               _child ->
                 false
             end
           )
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
