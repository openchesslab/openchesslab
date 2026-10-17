defmodule OpenChessLab.Repo.Migrations.UnwrapJsonbStringColumns do
  use Ecto.Migration

  # Rows written before the encoding fix stored JSON values double-encoded:
  # the jsonb column holds a JSON string instead of the object or array.
  def up do
    execute("""
    UPDATE position_feature_vectors
    SET features = (features #>> '{}')::jsonb
    WHERE jsonb_typeof(features) = 'string'
    """)

    execute("""
    UPDATE position_tablebases
    SET result = (result #>> '{}')::jsonb
    WHERE jsonb_typeof(result) = 'string'
    """)

    execute("""
    UPDATE position_evals
    SET lines = (lines #>> '{}')::jsonb
    WHERE jsonb_typeof(lines) = 'string'
    """)
  end

  def down do
    :ok
  end
end
