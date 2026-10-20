defmodule OpenChessLab.Repo.Migrations.AddRoomMemberRoles do
  use Ecto.Migration

  def change do
    alter table(:room_members) do
      add :role, :text
    end

    # The owner's membership row exists from create_private; every other
    # pre-roles member keeps today's behavior as an editor.
    execute(
      """
      UPDATE room_members AS rm
      SET role = 'owner'
      FROM rooms AS r
      WHERE r.id = rm.room_id AND r.owner_user_id = rm.user_id
      """,
      ""
    )

    execute("UPDATE room_members SET role = 'editor' WHERE role IS NULL", "")

    alter table(:room_members) do
      modify :role, :text, null: false
    end

    create constraint(
             :room_members,
             :room_members_role_check,
             check: "role IN ('owner', 'editor', 'viewer')"
           )
  end
end
