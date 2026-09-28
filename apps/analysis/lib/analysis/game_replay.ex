defmodule Analysis.GameReplay do
  @moduledoc """
  Replays canonical game content.

  The initial position is resolved from the content's
  `initial_position_id`. GameReplay does not depend on a concrete
  position store; the caller supplies the resolver.
  """

  alias Analysis.GameContent
  alias Chess.Move
  alias Chess.Position

  @type ply :: pos_integer()
  @type occurrence :: {Move.t(), Position.t()}

  @type position_resolver ::
          (GameContent.position_id() ->
             {:ok, Position.t()}
             | :not_found
             | {:error, term()})

  @spec replay(GameContent.t(), position_resolver()) ::
          {:ok, [occurrence()]}
          | {:error, {:position_not_found, GameContent.position_id()}}
          | {:error, {:illegal_move, ply()}}
          | {:error, term()}
  def replay(
        %GameContent{} = content,
        resolver
      )
      when is_function(resolver, 1) do
    position_id =
      GameContent.initial_position_id(content)

    case resolver.(position_id) do
      {:ok, %Position{} = initial_position} ->
        replay_moves(
          GameContent.moves(content),
          initial_position
        )

      :not_found ->
        {:error, {:position_not_found, position_id}}

      {:error, _reason} = error ->
        error
    end
  end

  defp replay_moves(
         moves,
         initial_position
       ) do
    moves
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      {:ok, initial_position, []},
      fn {move, ply}, {:ok, position, occurrences} ->
        case Position.apply_move(
               position,
               move
             ) do
          {:ok, next_position} ->
            {:cont,
             {:ok, next_position,
              [
                {move, next_position}
                | occurrences
              ]}}

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
