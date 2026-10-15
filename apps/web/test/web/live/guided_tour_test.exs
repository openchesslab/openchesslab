defmodule Web.GuidedTourTest do
  use Web.ConnCase, async: false

  alias Analysis.Rooms

  setup do
    code = "GT" <> Base.encode16(:crypto.strong_rand_bytes(4))
    {:ok, _room} = Rooms.start_room(code)
    on_exit(fn -> Rooms.stop_room(code) end)
    %{code: code}
  end

  test "the tour walks every feature, naming an anchor that exists in the room", %{code: code} do
    {:ok, view, _html} = live(build_conn(), "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    refute has_element?(view, "#tour-overlay")

    view |> element("#help-tour") |> render_click()

    targets = ~w(board analyses moves engine import search help)
    assert Web.Layouts.tour_steps_count() == length(targets)

    for {target, index} <- Enum.with_index(targets, 1) do
      assert has_element?(view, "#tour-overlay[data-tour-target='#{target}']")
      assert has_element?(view, "#tour-overlay [data-tour-ring]")
      assert has_element?(view, "#tour-overlay [data-tour-card][role='dialog']")
      assert has_element?(view, "#tour-overlay", "Step #{index} of #{length(targets)}")

      # The step's anchor exists, so the hook has something real to highlight.
      assert has_element?(view, "[data-tour='#{target}']")

      view |> element("#tour-overlay [phx-click='tour-next']") |> render_click()
    end

    # Next on the last step finishes the tour.
    refute has_element?(view, "#tour-overlay")
  end

  test "tour steps move back and forth and Escape-away closes", %{code: code} do
    {:ok, view, _html} = live(build_conn(), "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    view |> element("#help-tour") |> render_click()
    assert has_element?(view, "#tour-overlay[data-tour-target='board']")

    view |> element("#tour-overlay [phx-click='tour-next']") |> render_click()
    assert has_element?(view, "#tour-overlay[data-tour-target='analyses']")

    view |> element("#tour-overlay [phx-click='tour-back']") |> render_click()
    assert has_element?(view, "#tour-overlay[data-tour-target='board']")

    # Back on the first step is disabled — the tour cannot leave its start.
    assert has_element?(view, "#tour-overlay [phx-click='tour-back'][disabled]")

    render_click(view, "close-modal", %{})
    refute has_element?(view, "#tour-overlay")
  end

  test "the tour is translated", %{code: code} do
    {:ok, view, _html} = live(build_conn(), "/rooms/#{code}?locale=nl")
    render_click(view, "create-analysis", %{})

    view |> element("#help-tour") |> render_click()
    assert has_element?(view, "#tour-overlay", Web.I18n.t("tour.boardTitle", "nl"))
    assert has_element?(view, "#tour-overlay", "Stap 1 van 7")
  end
end
