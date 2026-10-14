defmodule OpenChessLab.Repo.Migrations.RequireRoomMemberDisplayNames do
  use Ecto.Migration

  def up do
    # Greenfield, no users to preserve: the only rows without a stored name
    # predate the requirement by a day and are dropped rather than backfilled.
    execute("DELETE FROM room_members WHERE display_name IS NULL")

    alter table(:room_members) do
      modify :display_name, :text, null: false
    end
  end

  def down do
    alter table(:room_members) do
      modify :display_name, :text, null: true
    end
  end
end
