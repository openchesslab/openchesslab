defmodule OpenChessLab.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :text, primary_key: true
    end

    create constraint(:rooms, :rooms_id_not_empty, check: "char_length(id) > 0")

    create table(:room_analyses) do
      add :room_id, references(:rooms, column: :id, type: :text, on_delete: :delete_all),
        null: false

      add :analysis_id, :text, null: false
    end

    create constraint(
             :room_analyses,
             :room_analyses_analysis_id_not_empty,
             check: "char_length(analysis_id) > 0"
           )

    create unique_index(:room_analyses, [:room_id, :analysis_id])
  end
end
