defmodule OpenChessLab.Repo.Migrations.CreatePositionDigests do
  use Ecto.Migration

  # The searchable feature digest: one row per position with its atom ids
  # (see feature_atoms). The GIN index serves `atom_ids @> [...]` lookups.
  def change do
    create table(:position_digests, primary_key: false) do
      add :position_id,
          references(:positions, type: :bigint, on_delete: :delete_all),
          primary_key: true,
          null: false

      add :atom_ids, {:array, :integer}, null: false, default: fragment("'{}'::integer[]")
    end

    create index(:position_digests, [:atom_ids],
             using: "GIN",
             name: :position_digests_atom_ids_gin
           )
  end
end
