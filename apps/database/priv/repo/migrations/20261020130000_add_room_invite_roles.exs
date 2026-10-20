defmodule OpenChessLab.Repo.Migrations.AddRoomInviteRoles do
  use Ecto.Migration

  def change do
    alter table(:room_invites) do
      # Every link admits exactly one role; pre-roles links admitted editors.
      add :role, :text, null: false, default: "editor"
    end

    create constraint(
             :room_invites,
             :room_invites_role_check,
             check: "role IN ('editor', 'viewer')"
           )

    # At most one active link per room per role; rotation revokes first.
    create unique_index(
             :room_invites,
             [:room_id, :role],
             where: "revoked_at IS NULL",
             name: :room_invites_one_active_per_role
           )
  end
end
