defmodule OpenChessLab.Repo.Migrations.AddRoomMemberDisplayNames do
  use Ecto.Migration

  def change do
    alter table(:room_members) do
      add :display_name, :text
    end
  end
end
