defmodule OpenChessLab.Repo.Migrations.AddPositionTablebases do
  use Ecto.Migration

  def change do
    create table(:position_tablebases, primary_key: false) do
      add :position_id, references(:positions, on_delete: :delete_all), primary_key: true
      add :result, :map, null: false
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end
  end
end
