defmodule OpenChessLab.Repo.Migrations.CreateUserSessions do
  use Ecto.Migration

  def change do
    create table(:user_sessions, primary_key: false) do
      add :token_hash, :binary, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :created_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create constraint(:user_sessions, :user_sessions_token_hash_size,
             check: "octet_length(token_hash) = 32"
           )

    create constraint(:user_sessions, :user_sessions_expiry_after_creation,
             check: "expires_at > created_at"
           )

    create index(:user_sessions, [:user_id])
  end
end
