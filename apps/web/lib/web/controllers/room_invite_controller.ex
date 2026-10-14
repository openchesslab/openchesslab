defmodule Web.RoomInviteController do
  @moduledoc """
  Accept a private-room invite link.

  The token in the URL is the capability; the room code alone never grants
  entry. Guests are pointed at the room's gate and asked to log in and reopen
  the link; the link stays valid, so reopening after login joins the room.
  """

  use Web, :controller

  alias Analysis.Rooms

  def join(conn, %{"code" => code, "token" => token}) do
    code = String.upcase(code)

    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    if user = conn.assigns.current_user do
      case Rooms.consume_invite(code, user.id, token) do
        {:ok, :joined} ->
          redirect(conn, to: ~p"/rooms/#{code}")

        {:error, :invalid_invite} ->
          conn
          |> put_flash(:error, Web.I18n.t("room.inviteInvalid"))
          |> redirect(to: ~p"/rooms/#{code}")
      end
    else
      conn
      |> put_flash(:error, Web.I18n.t("room.privateGateLogin"))
      |> redirect(to: ~p"/rooms/#{code}")
    end
  end
end
