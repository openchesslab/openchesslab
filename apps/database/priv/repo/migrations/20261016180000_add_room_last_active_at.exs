defmodule OpenChessLab.Repo.Migrations.AddRoomLastActiveAt do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :last_active_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:rooms, [:last_active_at])
  end
end
