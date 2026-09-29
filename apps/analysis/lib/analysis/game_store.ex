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

  @opaque occurrence_cursor :: reference()

  @type occurrence_page ::
          {:ok, [Occurrence.t()], :done | occurrence_cursor()}
          | {:error, term()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:db]

    defstruct db: nil,
              cursors: %{}
  end

  defmodule CursorState do
    @moduledoc false

    @enforce_keys [:scan]

    defstruct scan: nil,
              pending_occurrence: nil
  end

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
    rescue
      ArgumentError ->
        false
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

  @spec occurrences_by_position_id(GameDB.position_id()) ::
          {:ok, [Occurrence.t()]}
          | {:error, term()}
  def occurrences_by_position_id(position_id) do
    GenServer.call(
      server(),
      {
        :occurrences_by_position_id,
        position_id
      }
    )
  end

  @spec occurrences_page(
          GameDB.position_id(),
          pos_integer()
        ) ::
          occurrence_page()
  def occurrences_page(
        position_id,
        page_size
      )
      when is_integer(page_size) and
             page_size > 0 do
    GenServer.call(
      server(),
      {
        :occurrences_page,
        position_id,
        page_size
      }
    )
  end

  @spec next_occurrences_page(
          occurrence_cursor(),
          pos_integer()
        ) ::
          occurrence_page()
  def next_occurrences_page(
        cursor,
        page_size
      )
      when is_reference(cursor) and
             is_integer(page_size) and
             page_size > 0 do
    GenServer.call(
      server(),
      {
        :next_occurrences_page,
        cursor,
        page_size
      }
    )
  end

  @spec close_occurrence_scan(occurrence_cursor()) :: :ok
  def close_occurrence_scan(cursor)
      when is_reference(cursor) do
    GenServer.call(
      server(),
      {
        :close_occurrence_scan,
        cursor
      }
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
     %State{
       db:
         GameDB.new(
           storage_module,
           storage
         )
     }}
  end

  @impl true
  def handle_call(
        :ping,
        _from,
        %State{} = state
      ) do
    {
      :reply,
      :ok,
      state
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
        %State{db: db} = state
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
          %{
            state
            | db: updated_db
          }
        }

      {:error, _reason} = error ->
        {
          :reply,
          error,
          state
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
        %State{db: db} = state
      ) do
    {
      :reply,
      GameDB.find(
        db,
        fingerprint,
        content
      ),
      state
    }
  end

  def handle_call(
        {:get, game_id},
        _from,
        %State{db: db} = state
      ) do
    {
      :reply,
      GameDB.get(
        db,
        game_id
      ),
      state
    }
  end

  def handle_call(
        {:load, game_id},
        _from,
        %State{db: db} = state
      ) do
    {
      :reply,
      load_game(
        db,
        game_id
      ),
      state
    }
  end

  def handle_call(
        {:occurrences, game_id},
        _from,
        %State{db: db} = state
      ) do
    {
      :reply,
      GameDB.occurrences(
        db,
        game_id
      ),
      state
    }
  end

  def handle_call(
        {
          :occurrences_by_position_id,
          position_id
        },
        _from,
        %State{db: db} = state
      ) do
    {
      :reply,
      GameDB.occurrences_by_position_id(
        db,
        position_id
      ),
      state
    }
  end

  def handle_call(
        {
          :occurrences_page,
          position_id,
          page_size
        },
        _from,
        %State{db: db} = state
      ) do
    cursor_state =
      %CursorState{
        scan:
          GameDB.scan_occurrences(
            db,
            position_id
          )
      }

    case take_occurrence_page(
           cursor_state,
           page_size
         ) do
      {:ok, occurrences, :done} ->
        {
          :reply,
          {
            :ok,
            occurrences,
            :done
          },
          state
        }

      {
        :ok,
        occurrences,
        %CursorState{} = cursor_state
      } ->
        cursor =
          make_ref()

        {
          :reply,
          {
            :ok,
            occurrences,
            cursor
          },
          put_cursor(
            state,
            cursor,
            cursor_state
          )
        }

      {:error, reason} ->
        {
          :reply,
          {:error, reason},
          state
        }
    end
  end

  def handle_call(
        {
          :next_occurrences_page,
          cursor,
          page_size
        },
        _from,
        %State{} = state
      ) do
    case Map.fetch(
           state.cursors,
           cursor
         ) do
      {:ok, cursor_state} ->
        continue_occurrence_scan(
          state,
          cursor,
          cursor_state,
          page_size
        )

      :error ->
        {
          :reply,
          {:error, :cursor_not_found},
          state
        }
    end
  end

  def handle_call(
        {
          :close_occurrence_scan,
          cursor
        },
        _from,
        %State{} = state
      ) do
    {
      :reply,
      :ok,
      delete_cursor(
        state,
        cursor
      )
    }
  end

  def handle_call(
        {
          :get_occurrence,
          occurrence_id
        },
        _from,
        %State{db: db} = state
      ) do
    {
      :reply,
      GameDB.get_occurrence(
        db,
        occurrence_id
      ),
      state
    }
  end

  def handle_call(
        :cardinality,
        _from,
        %State{db: db} = state
      ) do
    {
      :reply,
      GameDB.cardinality(db),
      state
    }
  end

  defp continue_occurrence_scan(
         state,
         cursor,
         cursor_state,
         page_size
       ) do
    case take_occurrence_page(
           cursor_state,
           page_size
         ) do
      {:ok, occurrences, :done} ->
        {
          :reply,
          {
            :ok,
            occurrences,
            :done
          },
          delete_cursor(
            state,
            cursor
          )
        }

      {
        :ok,
        occurrences,
        %CursorState{} = cursor_state
      } ->
        {
          :reply,
          {
            :ok,
            occurrences,
            cursor
          },
          put_cursor(
            state,
            cursor,
            cursor_state
          )
        }

      {:error, reason} ->
        {
          :reply,
          {:error, reason},
          delete_cursor(
            state,
            cursor
          )
        }
    end
  end

  defp take_occurrence_page(
         cursor_state,
         page_size
       ) do
    take_occurrence_page(
      cursor_state,
      page_size,
      []
    )
  end

  defp take_occurrence_page(
         cursor_state,
         0,
         reversed_occurrences
       ) do
    finish_occurrence_page(
      cursor_state,
      reversed_occurrences
    )
  end

  defp take_occurrence_page(
         cursor_state,
         remaining,
         reversed_occurrences
       ) do
    case next_occurrence(cursor_state) do
      {
        :ok,
        occurrence,
        cursor_state
      } ->
        take_occurrence_page(
          cursor_state,
          remaining - 1,
          [
            occurrence
            | reversed_occurrences
          ]
        )

      :done ->
        {
          :ok,
          Enum.reverse(reversed_occurrences),
          :done
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finish_occurrence_page(
         cursor_state,
         reversed_occurrences
       ) do
    case next_occurrence(cursor_state) do
      {
        :ok,
        occurrence,
        cursor_state
      } ->
        {
          :ok,
          Enum.reverse(reversed_occurrences),
          %{
            cursor_state
            | pending_occurrence: occurrence
          }
        }

      :done ->
        {
          :ok,
          Enum.reverse(reversed_occurrences),
          :done
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp next_occurrence(
         %CursorState{
           pending_occurrence: %Occurrence{} = occurrence
         } = cursor_state
       ) do
    {
      :ok,
      occurrence,
      %{
        cursor_state
        | pending_occurrence: nil
      }
    }
  end

  defp next_occurrence(
         %CursorState{
           scan: scan
         } = cursor_state
       ) do
    case GameDB.scan_occurrences_next(scan) do
      {
        :ok,
        occurrence,
        scan
      } ->
        {
          :ok,
          occurrence,
          %{
            cursor_state
            | scan: scan
          }
        }

      :done ->
        :done

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_cursor(
         state,
         cursor,
         cursor_state
       ) do
    %{
      state
      | cursors:
          Map.put(
            state.cursors,
            cursor,
            cursor_state
          )
    }
  end

  defp delete_cursor(
         state,
         cursor
       ) do
    %{
      state
      | cursors:
          Map.delete(
            state.cursors,
            cursor
          )
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
