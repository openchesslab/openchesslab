defmodule OpenChessLab.Repo.Migrations.AddMultipvToPositionEvals do
  use Ecto.Migration

  def up do
    alter table(:position_evals) do
      add :multipv, :integer, null: false, default: 1
      add :lines, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end

    # Existing rows carry only their top line; rebuild the lines array from it.
    execute("""
    UPDATE position_evals
    SET lines = jsonb_build_array(
      jsonb_strip_nulls(
        jsonb_build_object(
          'multipv', 1,
          'score_cp', eval_cp,
          'score_mate', mate,
          'pv', pv
        )
      )
    )
    WHERE pv IS NOT NULL
    """)
  end

  def down do
    alter table(:position_evals) do
      remove :multipv
      remove :lines
    end
  end
end
