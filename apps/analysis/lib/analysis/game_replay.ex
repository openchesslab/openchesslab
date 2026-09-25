defmodule Analysis.GameReplay do
  @moduledoc """
  Replays the canonical move sequence of a game from an initial position.
  """

  alias Analysis.Game
  alias Chess.Move
  alias Chess.Position

  @type ply :: pos_integer()
  @type occurrence :: {Move.t(), Position.t()}

  @spec replay(Game.t(), Position.t()) ::
          {:ok, [occurrence()]}
          | {:error, {:illegal_move, ply()}}
  def replay(%Game{} = game, %Position{} = initial_position) do
    game
    |> Game.moves()
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      {:ok, initial_position, []},
      fn {move, ply}, {:ok, position, occurrences} ->
        case Position.apply_move(position, move) do
          {:ok, next_position} ->
            {:cont, {:ok, next_position, [{move, next_position} | occurrences]}}

          {:error, :illegal_move} ->
            {:halt, {:error, {:illegal_move, ply}}}
        end
      end
    )
    |> case do
      {:ok, _final_position, occurrences} ->
        {:ok, Enum.reverse(occurrences)}

      {:error, _reason} = error ->
        error
    end
  end
end
