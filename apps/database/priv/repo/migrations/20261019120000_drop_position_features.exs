defmodule OpenChessLab.Repo.Migrations.DropPositionFeatures do
  use Ecto.Migration

  # The old property digest is fully replaced: pawn-structure predicates run
  # on the positions columns and catalogue features live in position_digests.
  # Nothing writes or reads position_features anymore.
  def change do
    drop table(:position_features)
  end
end
