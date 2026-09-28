defmodule Analysis.GameRecordStore do
  @moduledoc """
  Storage contract for concrete played-game records.

  Game records reference canonical chess content in GameDB through
  their `game_id`.

  The record id identifies the concrete played game. Multiple
  records may therefore reference the same canonical GameDB game.
  """

  alias Analysis.GameRecord

  @type store :: GenServer.server()

  @callback insert(
              store(),
              GameRecord.t()
            ) ::
              :ok
              | {:error, :already_exists}

  @callback get(
              store(),
              GameRecord.id()
            ) ::
              {:ok, GameRecord.t()}
              | :not_found

  @callback list(store()) ::
              [GameRecord.t()]
end
