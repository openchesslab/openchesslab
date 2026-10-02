defmodule Web.ReadinessControllerTest do
  use Web.ConnCase, async: false

  alias Analysis.AnalysisStore

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
