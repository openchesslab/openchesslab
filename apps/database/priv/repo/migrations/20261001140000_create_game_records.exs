defmodule OpenChessLab.Repo.Migrations.CreateGameRecords do
  use Ecto.Migration

  def change do
    create table(:game_records) do
      add :record_id,
          :text,
          null: false

      add :game_id,
          references(
            :games,
            type: :bigint
          ),
          null: false

      add :fullmove_number,
          :bigint,
          null: false

      add :metadata,
          :map,
          null: false
    end

    create constraint(
             :game_records,
             :game_records_record_id_not_empty,
             check: "char_length(record_id) > 0"
           )

    create constraint(
             :game_records,
             :game_records_fullmove_number_positive,
             check: "fullmove_number > 0"
           )

    create constraint(
             :game_records,
             :game_records_metadata_object,
             check: "jsonb_typeof(metadata) = 'object'"
           )

    create unique_index(
             :game_records,
             [:record_id],
             name: :game_records_record_id_unique
           )

    create index(
             :game_records,
             [:game_id, :id],
             name: :game_records_game_id_id_index
           )
  end
end
