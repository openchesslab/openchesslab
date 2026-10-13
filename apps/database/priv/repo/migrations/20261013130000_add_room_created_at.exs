defmodule OpenChessLab.Repo.Migrations.AddRoomCreatedAt do
  use Ecto.Migration

  def up do
    # The creation time of existing rooms is unknown. Keep it NULL instead
    # of inventing a creation date when this migration runs.
    execute("ALTER TABLE rooms ADD COLUMN created_at timestamptz")
    execute("ALTER TABLE rooms ALTER COLUMN created_at SET DEFAULT now()")

    create index(:rooms, [:created_at], name: :rooms_created_at_index)
  end

  def down do
    drop index(:rooms, [:created_at], name: :rooms_created_at_index)
    execute("ALTER TABLE rooms DROP COLUMN created_at")
  end
end
