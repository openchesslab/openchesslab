defmodule OpenChessLab.Repo.Migrations.AddMetadataTextTrigramIndexes do
  use Ecto.Migration

  # The search UI's free-text metadata filters run
  # `metadata ->> key ILIKE '%…%'` (player names, opening, event). A seq scan
  # per search is acceptable at ~280K records but not at the 10M-game target;
  # trigram GIN indexes serve those patterns directly. pg_trgm is a trusted
  # extension since PostgreSQL 13, so the migration role can enable it.
  # Plain transactional builds, same reasoning as AddBookQueryIndexes.
  @keys_to_indexes [
    {"white", "game_records_white_trgm_index"},
    {"black", "game_records_black_trgm_index"},
    {"opening", "game_records_opening_trgm_index"},
    {"event", "game_records_event_trgm_index"}
  ]

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    for {key, index} <- @keys_to_indexes do
      execute(
        "CREATE INDEX #{index} ON game_records USING gin ((metadata ->> '#{key}') gin_trgm_ops)"
      )
    end
  end

  # The extension stays: it may have existed before this migration, and other
  # databases on the same cluster share it.
  def down do
    for {_key, index} <- Enum.reverse(@keys_to_indexes) do
      execute("DROP INDEX IF EXISTS #{index}")
    end
  end
end
