defmodule Web.ReadinessControllerTest do
  use Web.ConnCase, async: false

  alias Analysis.GameStore
  alias Analysis.PositionStore

  test "GET /ready returns ready when required stores are reachable",
       %{conn: conn} do
    conn = get(conn, "/ready")

    assert json_response(conn, 200) == %{
             "status" => "ready"
           }
  end

  test "GET /ready returns service unavailable when the position store is unavailable",
       %{conn: conn} do
    previous =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    on_exit(fn ->
      restore_position_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      PositionStore,
      server: :unavailable_position_store
    )

    conn = get(conn, "/ready")

    assert json_response(conn, 503) == %{
             "status" => "unavailable"
           }
  end

  test "GET /ready returns service unavailable when the game store is unavailable",
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
      store: :unavailable_game_store
    )

    conn = get(conn, "/ready")

    assert json_response(conn, 503) == %{
             "status" => "unavailable"
           }
  end

  defp restore_position_store_config(:not_configured) do
    Application.delete_env(
      :analysis,
      PositionStore
    )
  end

  defp restore_position_store_config(value) do
    Application.put_env(
      :analysis,
      PositionStore,
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
end
