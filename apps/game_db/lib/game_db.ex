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
  def new(
        storage_module,
        storage
      )
      when is_atom(storage_module) do
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
        %__MODULE__{
          storage_module: storage_module,
          storage: storage
        } = db,
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
        %__MODULE__{
          storage_module: storage_module,
          storage: storage
        },
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
  def get(
        %__MODULE__{
          storage_module: storage_module,
          storage: storage
        },
        game_id
      ) do
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
  def occurrences(
        %__MODULE__{
          storage_module: storage_module,
          storage: storage
        },
        game_id
      ) do
    storage_module.occurrences(
      storage,
      game_id
    )
  end

  @spec get_occurrence(
          t(),
          occurrence_id()
        ) ::
          {:ok, Occurrence.t()}
          | :not_found
          | {:error, term()}
  def get_occurrence(
        %__MODULE__{
          storage_module: storage_module,
          storage: storage
        },
        occurrence_id
      ) do
    storage_module.get_occurrence(
      storage,
      occurrence_id
    )
  end

  @spec cardinality(t()) :: non_neg_integer()
  def cardinality(%__MODULE__{
        storage_module: storage_module,
        storage: storage
      }) do
    storage_module.cardinality(storage)
  end
end
