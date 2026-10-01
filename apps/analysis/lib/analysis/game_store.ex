defmodule Analysis.GameStore do
  @moduledoc """
  Application-facing access to canonical chess games.

  Game persistence is PostgreSQL-backed and stateless at the application
  layer. The configured repository owns durable game identity, occurrence
  identity and bounded occurrence paging.
  """

  alias Analysis.GameContent
  alias Analysis.GameOccurrence
  alias Analysis.GameRepository
  alias Analysis.GameRepository.Postgres

  @type game_id :: GameRepository.game_id()
  @type position_id :: GameRepository.position_id()
  @type occurrence_id :: GameRepository.occurrence_id()
  @type fingerprint :: GameRepository.fingerprint()
  @type occurrence_cursor :: GameRepository.occurrence_cursor()

  @type occurrence_page ::
          {:ok, [GameOccurrence.t()], :done | occurrence_cursor()}
          | {:error, term()}

  @spec repository() :: module()
  def repository do
    Application.get_env(
      :analysis,
      :game_repository,
      Postgres
    )
  end

  @spec ready?() :: boolean()
  def ready? do
    repository().ready?()
  end

  @spec put(
          fingerprint(),
          GameContent.t(),
          [position_id()]
        ) ::
          {:ok, game_id()}
          | {:error, term()}
  def put(fingerprint, content, position_ids) do
    repository().put(
      fingerprint,
      content,
      position_ids
    )
  end

  @spec find(
          fingerprint(),
          GameContent.t()
        ) ::
          {:ok, game_id()}
          | :not_found
          | {:error, term()}
  def find(fingerprint, content) do
    repository().find(
      fingerprint,
      content
    )
  end

  @spec get(game_id()) ::
          {:ok, GameContent.t()}
          | :not_found
          | {:error, term()}
  def get(game_id) do
    repository().get(game_id)
  end

  @spec load(game_id()) ::
          {:ok, GameContent.t(), [GameOccurrence.t()]}
          | :not_found
          | {:error, term()}
  def load(game_id) do
    case get(game_id) do
      {:ok, %GameContent{} = content} ->
        load_occurrences(
          game_id,
          content
        )

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  @spec occurrences(game_id()) ::
          {:ok, [GameOccurrence.t()]}
          | :not_found
          | {:error, term()}
  def occurrences(game_id) do
    repository().occurrences(game_id)
  end

  @spec occurrences_page(
          position_id(),
          pos_integer()
        ) :: occurrence_page()
  def occurrences_page(position_id, page_size) when is_integer(page_size) and page_size > 0 do
    repository().occurrences_page(
      position_id,
      page_size
    )
  end

  @spec next_occurrences_page(
          occurrence_cursor(),
          pos_integer()
        ) :: occurrence_page()
  def next_occurrences_page(cursor, page_size) when is_integer(page_size) and page_size > 0 do
    repository().next_occurrences_page(
      cursor,
      page_size
    )
  end

  @spec close_occurrence_scan(occurrence_cursor()) :: :ok
  def close_occurrence_scan(cursor) do
    repository().close_occurrences(cursor)
  end

  @spec get_occurrence(occurrence_id()) ::
          {:ok, GameOccurrence.t()}
          | :not_found
          | {:error, term()}
  def get_occurrence(occurrence_id) do
    repository().get_occurrence(occurrence_id)
  end

  defp load_occurrences(game_id, content) do
    case occurrences(game_id) do
      {:ok, occurrences} ->
        case validate_game_occurrences(
               game_id,
               content,
               occurrences
             ) do
          :ok ->
            {:ok, content, occurrences}

          {:error, _reason} = error ->
            error
        end

      :not_found ->
        {:error, :occurrences_not_found}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_game_occurrences(game_id, content, occurrences) when is_list(occurrences) do
    expected_count =
      length(GameContent.moves(content)) + 1

    initial_position_id =
      GameContent.initial_position_id(content)

    valid? =
      length(occurrences) == expected_count and
        valid_occurrence_sequence?(
          occurrences,
          game_id
        ) and
        initial_occurrence_matches?(
          occurrences,
          initial_position_id
        )

    if valid? do
      :ok
    else
      {:error, :invalid_occurrences}
    end
  end

  defp valid_occurrence_sequence?(occurrences, game_id) do
    occurrences
    |> Enum.with_index()
    |> Enum.all?(fn
      {
        %GameOccurrence{
          game_id: occurrence_game_id,
          ply: occurrence_ply,
          position_id: position_id
        },
        expected_ply
      }
      when is_integer(position_id) and position_id > 0 ->
        occurrence_game_id == game_id and
          occurrence_ply == expected_ply

      _other ->
        false
    end)
  end

  defp initial_occurrence_matches?(
         [%GameOccurrence{position_id: position_id} | _rest],
         expected_position_id
       ) do
    position_id == expected_position_id
  end

  defp initial_occurrence_matches?(_occurrences, _expected_position_id) do
    false
  end
end
