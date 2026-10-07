defmodule OpenChessLab.Repo.Migrations.OptimizePositionPawnStructureIndex do
  use Ecto.Migration

  def up do
    drop index(
           :positions,
           [
             :white_pawns,
             :black_pawns
           ],
           name: :positions_pawn_structure_index
         )

    create index(
             :positions,
             [
               :white_pawns,
               :black_pawns,
               :id
             ],
             name: :positions_pawn_structure_index
           )
  end

  def down do
    drop index(
           :positions,
           [
             :white_pawns,
             :black_pawns,
             :id
           ],
           name: :positions_pawn_structure_index
         )

    create index(
             :positions,
             [
               :white_pawns,
               :black_pawns
             ],
             name: :positions_pawn_structure_index
           )
  end
end
