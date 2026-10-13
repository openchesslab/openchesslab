defmodule OpenChessLab.Repo.Migrations.RequireRoomCreatedAt do
  use Ecto.Migration

  def up do
    execute("UPDATE rooms SET created_at = now() WHERE created_at IS NULL")
    execute("ALTER TABLE rooms ALTER COLUMN created_at SET NOT NULL")
  end

  def down do
    execute("ALTER TABLE rooms ALTER COLUMN created_at DROP NOT NULL")
  end
end
