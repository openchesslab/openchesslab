defmodule OpenChessLab.Repo.Migrations.GeneralizeOauthAttempts do
  use Ecto.Migration

  def change do
    rename table(:lichess_oauth_attempts), to: table(:oauth_attempts)
  end
end
