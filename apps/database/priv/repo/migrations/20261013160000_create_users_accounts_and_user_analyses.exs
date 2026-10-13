defmodule OpenChessLab.Repo.Migrations.CreateUsersAccountsAndUserAnalyses do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create table(:accounts) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :provider, :text, null: false
      add :subject_hmac, :binary, null: false
      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create constraint(:accounts, :accounts_provider_format,
             check: "provider ~ '^[a-z][a-z0-9_-]{0,31}$'"
           )

    create constraint(:accounts, :accounts_subject_hmac_size,
             check: "octet_length(subject_hmac) = 32"
           )

    create unique_index(:accounts, [:provider, :subject_hmac])
    create index(:accounts, [:user_id])

    create table(:user_analyses) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :analysis_id,
          references(:analyses, column: :analysis_id, type: :text, on_delete: :delete_all),
          null: false

      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:user_analyses, [:user_id, :analysis_id])
    create index(:user_analyses, [:analysis_id])
  end
end
