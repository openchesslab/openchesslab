defmodule OpenChessLab.Repo.Migrations.AddPositionPawnStructure do
  use Ecto.Migration

  def up do
    alter table(:positions) do
      add :white_pawns,
          :bigint

      add :black_pawns,
          :bigint
    end

    # PositionCodec stores one piece byte per square in bytes 0..63:
    #
    #   1 = white pawn
    #   7 = black pawn
    #
    # PostgreSQL bigint uses signed two's-complement representation, so
    # shifting into bit 63 intentionally produces a negative bigint.
    execute("""
    UPDATE positions AS p
    SET
      white_pawns = (
        SELECT
          COALESCE(
            bit_or(
              (1::bigint) << square
            ),
            0::bigint
          )
        FROM generate_series(
          0,
          63
        ) AS squares(square)
        WHERE get_byte(
          p.record,
          square
        ) = 1
      ),
      black_pawns = (
        SELECT
          COALESCE(
            bit_or(
              (1::bigint) << square
            ),
            0::bigint
          )
        FROM generate_series(
          0,
          63
        ) AS squares(square)
        WHERE get_byte(
          p.record,
          square
        ) = 7
      )
    """)

    execute("""
    ALTER TABLE positions
    ALTER COLUMN white_pawns SET NOT NULL
    """)

    execute("""
    ALTER TABLE positions
    ALTER COLUMN black_pawns SET NOT NULL
    """)

    create index(
             :positions,
             [
               :white_pawns,
               :black_pawns
             ],
             name: :positions_pawn_structure_index
           )
  end

  def down do
    drop index(
           :positions,
           [
             :white_pawns,
             :black_pawns
           ],
           name: :positions_pawn_structure_index
         )

    alter table(:positions) do
      remove :white_pawns
      remove :black_pawns
    end
  end
end
