defmodule Web.Gettext do
  @moduledoc """
  Gettext backend for the web application.
  """

  use Gettext.Backend,
    otp_app: :web,
    priv: "priv/gettext"
end
