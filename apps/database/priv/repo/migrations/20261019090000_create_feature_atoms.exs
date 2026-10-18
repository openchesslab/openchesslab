defmodule OpenChessLab.Repo.Migrations.CreateFeatureAtoms do
  use Ecto.Migration

  # The feature-digest dictionary: atom string → stable id. Append-only by
  # contract — ids are stored in position digests and must never change
  # meaning. The encoder registers atoms lazily at first sight.
  def change do
    create table(:feature_atoms) do
      add :atom, :text, null: false
    end

    create unique_index(:feature_atoms, [:atom])
  end
end
