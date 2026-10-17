defmodule OpenChessLab.Repo.Migrations.AddBookQueryIndexes do
  use Ecto.Migration

  # Plain (transactional) index builds on purpose: CREATE INDEX CONCURRENTLY
  # reproducibly killed the migration runner after the first statement.
  # These indexes are built during a deploy; the short write lock is fine
  # on a corpus with no concurrent bulk import running.
  def change do
    # The opening book scans every occurrence of one position and counts
    # distinct games; including game_id makes that scan index-only.
    create index(:game_occurrences, [:position_id, :move],
             include: [:game_id],
             name: :game_occurrences_position_move_covering_index
           )

    # The book's W/D/L counts join each occurrence to its records; this
    # covering index keeps that join index-only (no metadata heap fetches).
    create index(:game_records, ["game_id", "(metadata ->> 'result')", "id"],
             name: :game_records_result_covering_index
           )
  end
end
