defmodule OpenChessLab.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  def change do
    create table(:positions) do
      add :record, :binary, null: false
    end

    create constraint(
             :positions,
             :positions_record_size,
             check: "octet_length(record) = 67"
           )

    create unique_index(
             :positions,
             [:record],
             name: :positions_record_unique
           )

    create table(
             :position_features,
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

      add :properties,
          {:array, :binary},
          null: false,
          default: fragment("'{}'::bytea[]")
    end

    create index(
             :position_features,
             [:properties],
             using: "GIN",
             name: :position_features_properties_gin
           )
  end
end
