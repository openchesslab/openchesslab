defmodule OpenChessLab.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :fingerprint, :binary, null: false
      add :content, :binary, null: false
    end

    create constraint(
             :games,
             :games_fingerprint_size,
             check: "octet_length(fingerprint) = 32"
           )

    create constraint(
             :games,
             :games_content_minimum_size,
             check: "octet_length(content) >= 20"
           )

    create index(
             :games,
             [:fingerprint, :id],
             name: :games_fingerprint_id_index
           )

    create table(:game_occurrences) do
      add :game_id,
          references(
            :games,
            type: :bigint,
            on_delete: :delete_all
          ),
          null: false

      add :ply,
          :bigint,
          null: false

      add :position_id,
          references(
            :positions,
            type: :bigint
          ),
          null: false
    end

    create constraint(
             :game_occurrences,
             :game_occurrences_ply_non_negative,
             check: "ply >= 0"
           )

    create unique_index(
             :game_occurrences,
             [:game_id, :ply],
             name: :game_occurrences_game_id_ply_unique
           )

    create index(
             :game_occurrences,
             [:position_id, :id],
             name: :game_occurrences_position_id_id_index
           )
  end
end
