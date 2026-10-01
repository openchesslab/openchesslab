defmodule Web.ReadinessControllerTest do
  use Web.ConnCase, async: false

  alias Analysis.AnalysisStore
  alias Analysis.GameRecordStore

  defmodule UnavailablePositionRepository do
    @moduledoc false

    @behaviour Analysis.PositionRepository

    @impl true
    def ready?, do: false

    @impl true
    def put(_position), do: {:error, :unavailable}

    @impl true
    def get(_position_id), do: {:error, :unavailable}

    @impl true
    def find(_position), do: {:error, :unavailable}

    @impl true
    def query_page(_query, _page_size), do: {:error, :unavailable}

    @impl true
    def next_query_page(_cursor, _page_size), do: {:error, :unavailable}

    @impl true
    def close_query(_cursor), do: :ok
  end

  defmodule UnavailableGameRepository do
    @moduledoc false

    @behaviour Analysis.GameRepository

    @impl true
    def ready?, do: false

    @impl true
    def put(_fingerprint, _content, _position_ids), do: {:error, :unavailable}

    @impl true
    def find(_fingerprint, _content), do: {:error, :unavailable}

    @impl true
    def get(_game_id), do: {:error, :unavailable}

    @impl true
    def occurrences(_game_id), do: {:error, :unavailable}

    @impl true
    def occurrences_page(_position_id, _page_size), do: {:error, :unavailable}

    @impl true
    def next_occurrences_page(_cursor, _page_size), do: {:error, :unavailable}

    @impl true
    def close_occurrences(_cursor), do: :ok

    @impl true
    def get_occurrence(_occurrence_id), do: {:error, :unavailable}
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
      restore_repository(
        :position_repository,
        previous
      )
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

  test "GET /ready returns service unavailable when PostgreSQL game storage is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        :game_repository,
        :not_configured
      )

    on_exit(fn ->
      restore_repository(
        :game_repository,
        previous
      )
    end)

    Application.put_env(
      :analysis,
      :game_repository,
      UnavailableGameRepository
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
      restore_module_config(
        AnalysisStore,
        previous
      )
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

  test "GET /ready returns service unavailable when the game record store is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        GameRecordStore,
        :not_configured
      )

    on_exit(fn ->
      restore_module_config(
        GameRecordStore,
        previous
      )
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

  defp restore_repository(key, :not_configured) do
    Application.delete_env(
      :analysis,
      key
    )
  end

  defp restore_repository(key, repository) do
    Application.put_env(
      :analysis,
      key,
      repository
    )
  end

  defp restore_module_config(module, :not_configured) do
    Application.delete_env(
      :analysis,
      module
    )
  end

  defp restore_module_config(module, value) do
    Application.put_env(
      :analysis,
      module,
      value
    )
  end
end
