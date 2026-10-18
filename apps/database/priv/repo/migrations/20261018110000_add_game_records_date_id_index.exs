defmodule OpenChessLab.Repo.Migrations.AddGameRecordsDateIdIndex do
  use Ecto.Migration

  # Game-only corpus searches page newest-first. The sort key coalesces a
  # missing date to "" so undated records honestly sort last in descending
  # order; the (key, id) btree lets PostgreSQL walk the order instead of
  # sorting the whole record table per page. Plain transactional build,
  # same reasoning as AddBookQueryIndexes.
  def change do
    create index(
             :game_records,
             ["(COALESCE(metadata ->> 'date', ''))", "id"],
             name: :game_records_date_id_index
           )
  end
end
