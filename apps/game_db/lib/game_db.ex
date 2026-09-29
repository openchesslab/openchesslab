defmodule GameDB do
  @moduledoc """
  Public facade for canonical game storage.

  GameDB stores canonical chess content independently of concrete
  played-game metadata. Exact game identity is determined by the
  configured storage implementation using both the fingerprint and
  the complete game record.
  """

  alias GameDB.Occurrence
  alias GameDB.Storage

  @type storage_module :: module()

  @type t :: %__MODULE__{
          storage_module: storage_module(),
          storage: Storage.t()
        }

  @type game_id :: Storage.game_id()
  @type game_record :: Storage.game_record()
  @type fingerprint :: Storage.fingerprint()
  @type position_id :: Storage.position_id()
  @type occurrence_id :: Storage.occurrence_id()
  @opaque occurrence_scan ::
            {
              storage_module(),
              Storage.occurrence_scan_state()
            }

  @enforce_keys [
    :storage_module,
    :storage
  ]

  defstruct [
    :storage_module,
    :storage
  ]

  @spec new(
          storage_module(),
          Storage.t()
        ) :: t()
  def new(storage_module, storage) when is_atom(storage_module) do
    %__MODULE__{
      storage_module: storage_module,
      storage: storage
    }
  end

  @spec put(
          t(),
          fingerprint(),
          game_record(),
          [position_id()]
        ) ::
          {t(), game_id()}
          | {:error, term()}
  def put(
        %__MODULE__{storage_module: storage_module, storage: storage} = db,
        fingerprint,
        game_record,
        position_ids
      ) do
    case storage_module.put(
           storage,
           fingerprint,
           game_record,
           position_ids
         ) do
      {:ok, storage, game_id} ->
        {
          %{
            db
            | storage: storage
          },
          game_id
        }

      {:error, _reason} = error ->
        error
    end
  end

  @spec find(
          t(),
          fingerprint(),
          game_record()
        ) ::
          {:ok, game_id()}
          | :not_found
          | {:error, term()}
  def find(
        %__MODULE__{storage_module: storage_module, storage: storage},
        fingerprint,
        game_record
      ) do
    storage_module.find(
      storage,
      fingerprint,
      game_record
    )
  end

  @spec get(
          t(),
          game_id()
        ) ::
          {:ok, game_record()}
          | :not_found
          | {:error, term()}
  def get(%__MODULE__{storage_module: storage_module, storage: storage}, game_id) do
    storage_module.get(
      storage,
      game_id
    )
  end

  @spec occurrences(
          t(),
          game_id()
        ) ::
          {:ok, [Occurrence.t()]}
          | :not_found
          | {:error, term()}
  def occurrences(%__MODULE__{storage_module: storage_module, storage: storage}, game_id) do
    storage_module.occurrences(
      storage,
      game_id
    )
  end

  @spec occurrences_by_position_id(
          t(),
          position_id()
        ) ::
          {:ok, [Occurrence.t()]}
          | {:error, term()}
  def occurrences_by_position_id(
        %__MODULE__{storage_module: storage_module, storage: storage},
        position_id
      ) do
    storage_module.occurrences_by_position_id(
      storage,
      position_id
    )
  end

  @spec scan_occurrences(
          t(),
          position_id()
        ) ::
          occurrence_scan()
  def scan_occurrences(%__MODULE__{storage_module: storage_module, storage: storage}, position_id) do
    {
      storage_module,
      storage_module.scan_occurrences(
        storage,
        position_id
      )
    }
  end

  @spec scan_occurrences_next(occurrence_scan()) ::
          {:ok, Occurrence.t(), occurrence_scan()}
          | :done
          | {:error, term()}
  def scan_occurrences_next({storage_module, scan_state}) do
    case storage_module.scan_occurrences_next(scan_state) do
      {
        :ok,
        occurrence,
        next_scan_state
      } ->
        {
          :ok,
          occurrence,
          {
            storage_module,
            next_scan_state
          }
        }

      :done ->
        :done

      {:error, _reason} = error ->
        error
    end
  end

  @spec get_occurrence(
          t(),
          occurrence_id()
        ) ::
          {:ok, Occurrence.t()}
          | :not_found
          | {:error, term()}
  def get_occurrence(%__MODULE__{storage_module: storage_module, storage: storage}, occurrence_id) do
    storage_module.get_occurrence(
      storage,
      occurrence_id
    )
  end

  @spec cardinality(t()) :: non_neg_integer()
  def cardinality(%__MODULE__{storage_module: storage_module, storage: storage}) do
    storage_module.cardinality(storage)
  end
end
