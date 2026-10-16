defmodule OpenChessLab.Repo.Migrations.CreateProviderGrants do
  use Ecto.Migration

  def change do
    create table(:provider_grants) do
      # OAuth access tokens, encrypted at rest (AES-256-GCM in
      # Analysis.ProviderGrants). One live grant per user per provider.
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :provider, :text, null: false
      add :token_encrypted, :binary, null: false
      add :granted_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:provider_grants, [:user_id, :provider])
  end
end
