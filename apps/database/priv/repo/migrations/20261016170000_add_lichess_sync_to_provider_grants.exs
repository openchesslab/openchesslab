defmodule OpenChessLab.Repo.Migrations.AddLichessSyncToProviderGrants do
  use Ecto.Migration

  def change do
    alter table(:provider_grants) do
      add :sync_enabled, :boolean, null: false, default: false
      add :sync_cursor, :bigint
      add :synced_at, :utc_datetime_usec
    end
  end
end
