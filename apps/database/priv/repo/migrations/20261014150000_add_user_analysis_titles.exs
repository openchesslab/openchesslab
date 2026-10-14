defmodule OpenChessLab.Repo.Migrations.AddUserAnalysisTitles do
  use Ecto.Migration

  def change do
    alter table(:user_analyses) do
      add :title, :text
    end

    create constraint(:user_analyses, :user_analyses_title_length,
             check: "title IS NULL OR char_length(title) BETWEEN 1 AND 120"
           )
  end
end
