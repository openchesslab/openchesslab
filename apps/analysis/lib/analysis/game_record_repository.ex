defmodule Analysis.GameRecordRepository do
  @moduledoc """
  Persistence contract for concrete played-game records.

  A game record references durable canonical game content through its
  `game_id`.

  Repository implementations own durable record identity and bounded
  paging of records belonging to one canonical game.
  """

  alias Analysis.GameRecord
  alias Analysis.GameRepository

  @type record_id :: binary()
  @type record_cursor :: term()

  @type record_page ::
          {:ok, [GameRecord.t()], :done | record_cursor()}
          | {:error, term()}

  @callback ready?() :: boolean()

  @callback insert(GameRecord.t()) ::
              :ok
              | {:error, term()}

  @callback get(GameRecord.id()) ::
              {:ok, GameRecord.t()}
              | :not_found
              | {:error, term()}

  @callback records_page_by_game_id(
              GameRepository.game_id(),
              pos_integer()
            ) :: record_page()

  @callback next_records_page(
              record_cursor(),
              pos_integer()
            ) :: record_page()

  @callback close_records(record_cursor()) :: :ok
end
