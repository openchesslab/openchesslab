defmodule Analysis.GameStore do
  @moduledoc """
  Application-facing store for canonical chess games.

  GameStore owns the mutable GameDB state and exposes canonical
  game operations without leaking the physical storage backend.
  """

  use GenServer

  alias Analysis.GameContent
  alias GameDB.Occurrence
  alias GameDB.Storage.Memory, as: GameStorage

  @name __MODULE__

  @registry Analysis.GameStoreRegistry
  @registry_key :game_store

  @spec clustered_server() ::
          GenServer.server()
  def clustered_server do
    {
      :via,
      Horde.Registry,
      {
        @registry,
        @registry_key
      }
    }
  end

  @spec start_link(keyword()) ::
          GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name:
        Keyword.get(
          opts,
          :server,
          @name
        )
    )
  end

  @spec server() ::
          GenServer.server()
  def server do
    Application.get_env(
      :analysis,
      __MODULE__,
      []
    )
    |> Keyword.get(
      :server,
      clustered_server()
    )
  end

  @spec ready?() :: boolean()
  def ready? do
    try do
      GenServer.call(
        server(),
        :ping,
        1_000
      ) == :ok
    catch
      :exit, _reason ->
        false
    end
  end

  @spec put(
          GameDB.fingerprint(),
          GameContent.t(),
          [GameDB.position_id()]
        ) ::
          {:ok, GameDB.game_id()}
          | {:error, term()}
  def put(
        fingerprint,
        %GameContent{} = content,
        position_ids
      ) do
    GenServer.call(
      server(),
      {
        :put,
        fingerprint,
        content,
        position_ids
      }
    )
  end

  @spec find(
          GameDB.fingerprint(),
          GameContent.t()
        ) ::
          {:ok, GameDB.game_id()}
          | :not_found
          | {:error, term()}
  def find(
        fingerprint,
        %GameContent{} = content
      ) do
    GenServer.call(
      server(),
      {
        :find,
        fingerprint,
        content
      }
    )
  end

  @spec get(GameDB.game_id()) ::
          {:ok, GameContent.t()}
          | :not_found
          | {:error, term()}
  def get(game_id) do
    GenServer.call(
      server(),
      {:get, game_id}
    )
  end

  @spec occurrences(GameDB.game_id()) ::
          {:ok, [Occurrence.t()]}
          | :not_found
          | {:error, term()}
  def occurrences(game_id) do
    GenServer.call(
      server(),
      {:occurrences, game_id}
    )
  end

  @spec get_occurrence(GameDB.occurrence_id()) ::
          {:ok, Occurrence.t()}
          | :not_found
          | {:error, term()}
  def get_occurrence(occurrence_id) do
    GenServer.call(
      server(),
      {
        :get_occurrence,
        occurrence_id
      }
    )
  end

  @spec cardinality() ::
          non_neg_integer()
  def cardinality do
    GenServer.call(
      server(),
      :cardinality
    )
  end

  @impl true
  def init(opts) do
    {
      storage_module,
      storage
    } =
      Keyword.get_lazy(
        opts,
        :storage,
        fn ->
          {
            GameStorage,
            GameStorage.new()
          }
        end
      )

    {:ok,
     GameDB.new(
       storage_module,
       storage
     )}
  end

  @impl true
  def handle_call(
        :ping,
        _from,
        db
      ) do
    {
      :reply,
      :ok,
      db
    }
  end

  def handle_call(
        {
          :put,
          fingerprint,
          content,
          position_ids
        },
        _from,
        db
      ) do
    case GameDB.put(
           db,
           fingerprint,
           content,
           position_ids
         ) do
      {
        %GameDB{} = updated_db,
        game_id
      } ->
        {
          :reply,
          {:ok, game_id},
          updated_db
        }

      {:error, _reason} = error ->
        {
          :reply,
          error,
          db
        }
    end
  end

  def handle_call(
        {
          :find,
          fingerprint,
          content
        },
        _from,
        db
      ) do
    {
      :reply,
      GameDB.find(
        db,
        fingerprint,
        content
      ),
      db
    }
  end

  def handle_call(
        {:get, game_id},
        _from,
        db
      ) do
    {
      :reply,
      GameDB.get(
        db,
        game_id
      ),
      db
    }
  end

  def handle_call(
        {:occurrences, game_id},
        _from,
        db
      ) do
    {
      :reply,
      GameDB.occurrences(
        db,
        game_id
      ),
      db
    }
  end

  def handle_call(
        {
          :get_occurrence,
          occurrence_id
        },
        _from,
        db
      ) do
    {
      :reply,
      GameDB.get_occurrence(
        db,
        occurrence_id
      ),
      db
    }
  end

  def handle_call(
        :cardinality,
        _from,
        db
      ) do
    {
      :reply,
      GameDB.cardinality(db),
      db
    }
  end
end
