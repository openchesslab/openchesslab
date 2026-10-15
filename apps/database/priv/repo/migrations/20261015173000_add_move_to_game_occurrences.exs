defmodule OpenChessLab.Repo.Migrations.AddMoveToGameOccurrences do
  use Ecto.Migration

  def change do
    alter table(:game_occurrences) do
      add :move, :text
    end

    # The book tab aggregates "moves played from this position".
    create index(:game_occurrences, [:position_id, :move])
  end
end
