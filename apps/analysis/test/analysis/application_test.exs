defmodule Analysis.ApplicationTest do
  use ExUnit.Case, async: false

  alias Analysis.AnalysisStore
  alias Analysis.AnalysisStore.Dets
  alias Analysis.AnalysisStore.Memory
  alias Analysis.AnalysisStoreOwner
  alias Analysis.Application, as: AnalysisApplication
  alias Analysis.GameRecordStore
  alias Analysis.GameRecordStoreOwner

  setup do
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
        AnalysisStoreOwner,
        previous_analysis_store_owner
      )

      restore_config(
        AnalysisStore,
        previous_analysis_store
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
      AnalysisStoreOwner
    )

    Application.delete_env(
      :analysis,
      AnalysisStore
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

  test "does not start a legacy position store process" do
    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {Analysis.PositionStore, _options} ->
                 true

               _child ->
                 false
             end
           )
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

  test "does not start a canonical game store process" do
    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {Analysis.GameStore, _options} -> true
               _child -> false
             end
           )
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
