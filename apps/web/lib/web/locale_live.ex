defmodule Web.LocaleLive do
  @moduledoc """
  Restores the locale for LiveView processes.

  The locale is discovered and persisted by localize_web during the
  initial HTTP request. LiveView processes restore that locale from
  the session and apply it to both Localize and Gettext.
  """

  @spec on_mount(
          :default,
          map(),
          map(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:cont, Phoenix.LiveView.Socket.t()}

  def on_mount(:default, _params, session, socket) do
    {:ok, _locale} =
      Localize.Plug.put_locale_from_session(
        session,
        gettext: Web.Gettext
      )

    {:cont,
     Phoenix.Component.assign(
       socket,
       :locale,
       Gettext.get_locale(Web.Gettext)
     )}
  end
end
