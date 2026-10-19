defmodule OpenChessLab.Repo.Migrations.AddIntarrayExtension do
  use Ecto.Migration

  # The intarray operators (`&`, `-`, `+` on integer arrays) power the
  # similar-search rerank: cardinality(atom_ids & query_atoms) counts shared
  # digest atoms. Trusted since PostgreSQL 13, like pg_trgm.
  def up do
    execute("CREATE EXTENSION IF NOT EXISTS intarray")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS intarray")
  end
end
