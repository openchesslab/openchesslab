defmodule OpenChessLab.Repo.Migrations.AddUserSessionsExpiryIndex do
  use Ecto.Migration

  def change do
    create index(:user_sessions, [:expires_at, :token_hash])
  end
end
