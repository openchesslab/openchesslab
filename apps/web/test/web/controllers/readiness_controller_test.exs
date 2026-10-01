defmodule Web.ReadinessControllerTest do
  use Web.ConnCase, async: false

  alias Analysis.AnalysisStore
  alias Analysis.GameRecordStore
  alias Analysis.GameStore

  defmodule UnavailablePositionRepository do
    @moduledoc false

    @behaviour Analysis.PositionRepository

    @impl true
    def ready? do
      false
    end

    @impl true
    def put(_position) do
      {:error, :unavailable}
    end

    @impl true
    def get(_position_id) do
      {:error, :unavailable}
    end

    @impl true
    def find(_position) do
      {:error, :unavailable}
    end

    @impl true
    def query_page(_query, _page_size) do
      {:error, :unavailable}
    end

    @impl true
    def next_query_page(_cursor, _page_size) do
      {:error, :unavailable}
    end

    @impl true
    def close_query(_cursor) do
      :ok
    end
  end

  test "GET /ready returns ready when required stores are reachable",
       %{conn: conn} do
    conn =
      get(
        conn,
        "/ready"
      )

    assert json_response(
             conn,
             200
           ) ==
             %{
               "status" => "ready"
             }
  end

  test "GET /ready returns service unavailable when PostgreSQL position storage is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        :position_repository,
        :not_configured
      )

    on_exit(fn ->
      restore_position_repository(previous)
    end)

    Application.put_env(
      :analysis,
      :position_repository,
      UnavailablePositionRepository
    )

    conn =
      get(
        conn,
        "/ready"
      )

    assert json_response(
             conn,
             503
           ) ==
             %{
               "status" => "unavailable"
             }
  end

  test "GET /ready returns service unavailable when the analysis store is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        AnalysisStore,
        :not_configured
      )

    on_exit(fn ->
      restore_analysis_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      AnalysisStore,
      store: :unavailable_analysis_store
    )

    conn =
      get(
        conn,
        "/ready"
      )

    assert json_response(
             conn,
             503
           ) ==
             %{
               "status" => "unavailable"
             }
  end

  test "GET /ready returns service unavailable when the canonical game store is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        GameStore,
        :not_configured
      )

    on_exit(fn ->
      restore_game_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      GameStore,
      server: :unavailable_game_store
    )

    conn =
      get(
        conn,
        "/ready"
      )

    assert json_response(
             conn,
             503
           ) ==
             %{
               "status" => "unavailable"
             }
  end

  test "GET /ready returns service unavailable when the game record store is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        GameRecordStore,
        :not_configured
      )

    on_exit(fn ->
      restore_game_record_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      GameRecordStore,
      store: :unavailable_game_record_store
    )

    conn =
      get(
        conn,
        "/ready"
      )

    assert json_response(
             conn,
             503
           ) ==
             %{
               "status" => "unavailable"
             }
  end

  test "GET /ready returns service unavailable when a Horde registry is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        GameStore,
        :not_configured
      )

    on_exit(fn ->
      restore_game_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      GameStore,
      server: {
        :via,
        Horde.Registry,
        {
          :unavailable_game_store_registry,
          :game_store
        }
      }
    )

    conn =
      get(
        conn,
        "/ready"
      )

    assert json_response(
             conn,
             503
           ) ==
             %{
               "status" => "unavailable"
             }
  end

  defp restore_position_repository(:not_configured) do
    Application.delete_env(
      :analysis,
      :position_repository
    )
  end

  defp restore_position_repository(repository) do
    Application.put_env(
      :analysis,
      :position_repository,
      repository
    )
  end

  defp restore_analysis_store_config(:not_configured) do
    Application.delete_env(
      :analysis,
      AnalysisStore
    )
  end

  defp restore_analysis_store_config(value) do
    Application.put_env(
      :analysis,
      AnalysisStore,
      value
    )
  end

  defp restore_game_store_config(:not_configured) do
    Application.delete_env(
      :analysis,
      GameStore
    )
  end

  defp restore_game_store_config(value) do
    Application.put_env(
      :analysis,
      GameStore,
      value
    )
  end

  defp restore_game_record_store_config(:not_configured) do
    Application.delete_env(
      :analysis,
      GameRecordStore
    )
  end

  defp restore_game_record_store_config(value) do
    Application.put_env(
      :analysis,
      GameRecordStore,
      value
    )
  end
end
