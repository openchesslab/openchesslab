defmodule GameDB.Storage.Memory do
  @moduledoc """
  In-memory reference implementation of GameDB storage.
  """

  @behaviour GameDB.Storage

  alias GameDB.Occurrence
  alias GameDB.Storage

  @type game_id :: Storage.game_id()
  @type occurrence_id :: Storage.occurrence_id()
  @type occurrence_scan_state :: %{
          storage: t(),
          occurrence_ids: [occurrence_id()]
        }

  @type t :: %__MODULE__{
          games: %{game_id() => Storage.game_record()},
          fingerprints: %{game_id() => Storage.fingerprint()},
          fingerprint_index: %{
            Storage.fingerprint() => MapSet.t(game_id())
          },
          occurrence_ids_by_game: %{
            game_id() => [occurrence_id()]
          },
          occurrence_ids_by_position: %{
            Storage.position_id() => [occurrence_id()]
          },
          occurrences: %{
            occurrence_id() => Occurrence.t()
          },
          next_game_id: game_id(),
          next_occurrence_id: occurrence_id()
        }

  defstruct games: %{},
            fingerprints: %{},
            fingerprint_index: %{},
            occurrence_ids_by_game: %{},
            occurrence_ids_by_position: %{},
            occurrences: %{},
            next_game_id: 1,
            next_occurrence_id: 1

  @type scan_state :: %{
          storage: t(),
          next_game_id: game_id()
        }

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @impl Storage
  def put(%__MODULE__{} = storage, fingerprint, record, position_ids)
      when is_binary(fingerprint) and is_list(position_ids) do
    with :ok <- validate_position_ids(position_ids) do
      case find(
             storage,
             fingerprint,
             record
           ) do
        {:ok, game_id} ->
          {:ok, storage, game_id}

        :not_found ->
          put_new(
            storage,
            fingerprint,
            record,
            position_ids
          )
      end
    end
  end

  def put(%__MODULE__{}, _fingerprint, _record, _position_ids) do
    {:error, :invalid_fingerprint}
  end

  @impl Storage
  def find(%__MODULE__{} = storage, fingerprint, record) when is_binary(fingerprint) do
    storage.fingerprint_index
    |> Map.get(
      fingerprint,
      MapSet.new()
    )
    |> Enum.find_value(
      :not_found,
      fn game_id ->
        if Map.fetch!(
             storage.games,
             game_id
           ) == record do
          {:ok, game_id}
        end
      end
    )
  end

  @impl Storage
  def get(%__MODULE__{} = storage, game_id) do
    case Map.fetch(
           storage.games,
           game_id
         ) do
      {:ok, record} ->
        {:ok, record}

      :error ->
        :not_found
    end
  end

  @impl Storage
  def occurrences(%__MODULE__{} = storage, game_id) do
    case Map.fetch(
           storage.occurrence_ids_by_game,
           game_id
         ) do
      {:ok, occurrence_ids} ->
        {:ok,
         Enum.map(
           occurrence_ids,
           &Map.fetch!(
             storage.occurrences,
             &1
           )
         )}

      :error ->
        :not_found
    end
  end

  @impl Storage
  def scan_occurrences(%__MODULE__{} = storage, position_id) do
    %{
      storage: storage,
      occurrence_ids:
        Map.get(
          storage.occurrence_ids_by_position,
          position_id,
          []
        )
    }
  end

  @impl Storage
  def scan_occurrences_next(
        %{storage: storage, occurrence_ids: [occurrence_id | remaining]} = scan
      ) do
    case Map.fetch(
           storage.occurrences,
           occurrence_id
         ) do
      {:ok, occurrence} ->
        {
          :ok,
          occurrence,
          %{
            scan
            | occurrence_ids: remaining
          }
        }

      :error ->
        {:error, :occurrence_not_found}
    end
  end

  def scan_occurrences_next(%{occurrence_ids: []}) do
    :done
  end

  @impl Storage
  def occurrences_by_position_id(%__MODULE__{} = storage, position_id) do
    occurrences =
      storage.occurrence_ids_by_position
      |> Map.get(
        position_id,
        []
      )
      |> Enum.map(
        &Map.fetch!(
          storage.occurrences,
          &1
        )
      )

    {:ok, occurrences}
  end

  @impl Storage
  def get_occurrence(%__MODULE__{} = storage, occurrence_id) do
    case Map.fetch(
           storage.occurrences,
           occurrence_id
         ) do
      {:ok, occurrence} ->
        {:ok, occurrence}

      :error ->
        :not_found
    end
  end

  @impl Storage
  def scan(%__MODULE__{} = storage) do
    %{
      storage: storage,
      next_game_id: 1
    }
  end

  @impl Storage
  def scan_next(%{storage: storage, next_game_id: game_id} = state) do
    if game_id < storage.next_game_id do
      {:ok, game_id,
       %{
         state
         | next_game_id: game_id + 1
       }}
    else
      :done
    end
  end

  @impl Storage
  def cardinality(%__MODULE__{games: games}) do
    map_size(games)
  end

  defp validate_position_ids([]) do
    {:error, :missing_initial_position}
  end

  defp validate_position_ids(position_ids) do
    if Enum.all?(
         position_ids,
         &(is_integer(&1) and &1 > 0)
       ) do
      :ok
    else
      {:error, :invalid_position_ids}
    end
  end

  defp put_new(storage, fingerprint, record, position_ids) do
    game_id =
      storage.next_game_id

    {occurrences, next_occurrence_id} =
      build_occurrences(
        game_id,
        position_ids,
        storage.next_occurrence_id
      )

    occurrence_ids_by_position =
      index_occurrences_by_position(
        storage.occurrence_ids_by_position,
        occurrences
      )

    occurrence_ids =
      Enum.map(
        occurrences,
        & &1.id
      )

    occurrence_map =
      Map.new(
        occurrences,
        &{&1.id, &1}
      )

    storage = %{
      storage
      | games:
          Map.put(
            storage.games,
            game_id,
            record
          ),
        fingerprints:
          Map.put(
            storage.fingerprints,
            game_id,
            fingerprint
          ),
        fingerprint_index:
          Map.update(
            storage.fingerprint_index,
            fingerprint,
            MapSet.new([game_id]),
            &MapSet.put(&1, game_id)
          ),
        occurrence_ids_by_game:
          Map.put(
            storage.occurrence_ids_by_game,
            game_id,
            occurrence_ids
          ),
        occurrence_ids_by_position: occurrence_ids_by_position,
        occurrences:
          Map.merge(
            storage.occurrences,
            occurrence_map
          ),
        next_game_id: game_id + 1,
        next_occurrence_id: next_occurrence_id
    }

    {:ok, storage, game_id}
  end

  defp build_occurrences(game_id, position_ids, first_occurrence_id) do
    position_ids
    |> Enum.with_index()
    |> Enum.map_reduce(
      first_occurrence_id,
      fn {position_id, ply}, occurrence_id ->
        occurrence =
          Occurrence.new(
            occurrence_id,
            game_id,
            ply,
            position_id
          )

        {
          occurrence,
          occurrence_id + 1
        }
      end
    )
  end

  defp index_occurrences_by_position(index, occurrences) do
    Enum.reduce(
      occurrences,
      index,
      fn %Occurrence{
           id: occurrence_id,
           position_id: position_id
         },
         index ->
        Map.update(
          index,
          position_id,
          [occurrence_id],
          &[occurrence_id | &1]
        )
      end
    )
  end
end
