defmodule Web.AnalysesLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Analyses
  alias Analysis.Rooms

  test "renders stored analyses", %{conn: conn} do
    analysis_id =
      "analysis-#{System.unique_integer([:positive])}"

    assert {:ok, _analysis, 1} =
             Analyses.create(analysis_id)

    {:ok, view, _html} =
      live(conn, "/analyses")

    assert has_element?(view, "h1", "Analyses")

    assert has_element?(
             view,
             "#analysis-#{analysis_id} .analysis-id",
             analysis_id
           )

    assert has_element?(
             view,
             "#analysis-#{analysis_id} .analysis-revision",
             "Revision 1"
           )
  end

  test "renders the analyses page in Dutch", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/analyses?locale=nl")

    assert has_element?(view, "h1", "Analyses")
  end

  test "opens a stored analysis in a room", %{conn: conn} do
    analysis_id =
      "analysis-#{System.unique_integer([:positive])}"

    room_id =
      "room-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Rooms.stop_room(room_id)
    end)

    assert {:ok, _analysis, 1} =
             Analyses.create(analysis_id)

    {:ok, view, _html} =
      live(conn, "/analyses")

    view
    |> form("#open-analysis-#{analysis_id}", %{
      "analysis_id" => analysis_id,
      "room" => %{"id" => room_id}
    })
    |> render_submit()

    assert_redirect(
      view,
      "/rooms/#{room_id}?analysis_id=#{analysis_id}"
    )

    assert {:ok, room} = Rooms.get(room_id)
    assert analysis_id in room.analysis_ids
  end
end
