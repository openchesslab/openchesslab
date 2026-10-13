defmodule OpenChessLab.Repo.Migrations.CreateLichessOauthAttempts do
  use Ecto.Migration

  def change do
    create table(:lichess_oauth_attempts, primary_key: false) do
      add :state_hash, :binary, primary_key: true
      add :browser_token_hash, :binary, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create constraint(:lichess_oauth_attempts, :lichess_oauth_attempts_hash_sizes,
             check: "octet_length(state_hash) = 32 AND octet_length(browser_token_hash) = 32"
           )

    create constraint(:lichess_oauth_attempts, :lichess_oauth_attempts_expiry_after_creation,
             check: "expires_at > created_at"
           )

    create index(:lichess_oauth_attempts, [:expires_at])
  end
end
