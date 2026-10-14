defmodule OpenChessLab.Repo.Migrations.AddPrivateRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :owner_user_id, references(:users, type: :uuid, on_delete: :delete_all)
    end

    create table(:room_members) do
      add :room_id, references(:rooms, column: :id, type: :text, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:room_members, [:room_id, :user_id])

    create table(:room_invites, primary_key: false) do
      add :token_hash, :binary, primary_key: true

      add :room_id, references(:rooms, column: :id, type: :text, on_delete: :delete_all),
        null: false

      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :revoked_at, :utc_datetime_usec
    end

    create constraint(:room_invites, :room_invites_token_hash_size,
             check: "octet_length(token_hash) = 32"
           )

    create constraint(:room_invites, :room_invites_revoked_after_creation,
             check: "revoked_at IS NULL OR revoked_at >= created_at"
           )

    create index(:room_invites, [:room_id])
  end
end
