defmodule OpenChessLab.Repo.Migrations.CreatePositionFeatureVectors do
  use Ecto.Migration

  def change do
    create table(
             :position_feature_vectors,
             primary_key: false
           ) do
      add :position_id,
          references(
            :positions,
            type: :bigint,
            on_delete: :delete_all
          ),
          primary_key: true,
          null: false

      add :version, :text, null: false
      add :fen, :text, null: false
      add :features, :map, null: false

      timestamps()
    end
  end
end
