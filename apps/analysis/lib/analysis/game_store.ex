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

  @spec load(GameDB.game_id()) ::
          {:ok, GameContent.t(), [Occurrence.t()]}
          | :not_found
          | {:error, term()}
  def load(game_id) do
    GenServer.call(
      server(),
      {:load, game_id}
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
        {:load, game_id},
        _from,
        db
      ) do
    {
      :reply,
      load_game(
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

  defp load_game(
         db,
         game_id
       ) do
    case GameDB.get(
           db,
           game_id
         ) do
      {:ok, %GameContent{} = content} ->
        load_game_occurrences(
          db,
          game_id,
          content
        )

      {:ok, _content} ->
        {:error, :invalid_game_content}

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  defp load_game_occurrences(
         db,
         game_id,
         content
       ) do
    case GameDB.occurrences(
           db,
           game_id
         ) do
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

  defp validate_game_occurrences(
         game_id,
         content,
         occurrences
       )
       when is_list(occurrences) do
    expected_count =
      length(GameContent.moves(content)) + 1

    initial_position_id =
      GameContent.initial_position_id(content)

    valid? =
      length(occurrences) ==
        expected_count and
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

  defp valid_occurrence_sequence?(
         occurrences,
         game_id
       ) do
    occurrences
    |> Enum.with_index()
    |> Enum.all?(fn
      {
        %Occurrence{
          game_id: occurrence_game_id,
          ply: occurrence_ply,
          position_id: position_id
        },
        expected_ply
      }
      when is_integer(position_id) and
             position_id > 0 ->
        occurrence_game_id ==
          game_id and
          occurrence_ply ==
            expected_ply

      _other ->
        false
    end)
  end

  defp initial_occurrence_matches?(
         [
           %Occurrence{
             position_id: position_id
           }
           | _rest
         ],
         expected_position_id
       ) do
    position_id ==
      expected_position_id
  end

  defp initial_occurrence_matches?(
         _occurrences,
         _expected_position_id
       ) do
    false
  end
end
