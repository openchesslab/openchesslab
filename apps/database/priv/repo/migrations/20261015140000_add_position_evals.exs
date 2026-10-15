defmodule OpenChessLab.Repo.Migrations.AddPositionEvals do
  use Ecto.Migration

  def change do
    create table(:position_evals, primary_key: false) do
      add :position_id, references(:positions, on_delete: :delete_all), null: false
      add :engine, :text, null: false
      add :depth, :integer, null: false
      add :eval_cp, :integer
      add :mate, :integer
      add :best_move, :text
      add :pv, :text
      add :nodes, :bigint
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:position_evals, [:position_id, :engine])
  end
end
