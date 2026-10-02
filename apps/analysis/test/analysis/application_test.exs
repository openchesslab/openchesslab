defmodule Analysis.ApplicationTest do
  use ExUnit.Case, async: false

  alias Analysis.Application, as: AnalysisApplication

  test "does not start legacy persistent store processes" do
    children =
      AnalysisApplication.children()

    refute Enum.any?(
             children,
             fn
               {Analysis.PositionStore, _options} ->
                 true

               {Analysis.GameStore, _options} ->
                 true

               {Analysis.AnalysisStore.Memory, _options} ->
                 true

               {Analysis.AnalysisStore.Dets, _options} ->
                 true

               _child ->
                 false
             end
           )
  end

  test "does not start an analysis store Horde registry" do
    refute Enum.any?(
             AnalysisApplication.children(),
             fn
               {
                 Horde.Registry,
                 options
               } ->
                 Keyword.get(
                   options,
                   :name
                 ) ==
                   Analysis.AnalysisStoreRegistry

               _child ->
                 false
             end
           )
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

  test "preserves the Room Horde registry" do
    assert {
             Horde.Registry,
             [
               name: Analysis.RoomRegistry,
               keys: :unique,
               members: :auto
             ]
           } in AnalysisApplication.children()
  end

  test "preserves the Room Horde dynamic supervisor" do
    assert {
             Horde.DynamicSupervisor,
             [
               name: Analysis.RoomSupervisor,
               strategy: :one_for_one,
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
