defmodule OpenChessLab.Repo.Migrations.CreateAnalyses do
  use Ecto.Migration

  def change do
    create table(:analyses) do
      add :analysis_id,
          :text,
          null: false

      add :revision,
          :bigint,
          null: false,
          default: 1

      add :record,
          :binary,
          null: false
    end

    create constraint(
             :analyses,
             :analyses_analysis_id_not_empty,
             check: "char_length(analysis_id) > 0"
           )

    create constraint(
             :analyses,
             :analyses_revision_positive,
             check: "revision > 0"
           )

    create constraint(
             :analyses,
             :analyses_record_minimum_size,
             check: "octet_length(record) > 8"
           )

    create unique_index(
             :analyses,
             [:analysis_id],
             name: :analyses_analysis_id_unique
           )
  end
end
