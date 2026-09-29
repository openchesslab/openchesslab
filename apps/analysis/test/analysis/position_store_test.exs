defmodule Analysis.PositionStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square
  alias PositionDB.Query

  test "registers under the configured server name" do
    server =
      :"position-store-#{System.unique_integer([:positive])}"

    assert {:ok, pid} =
             PositionStore.start_link(server: server)

    assert Process.whereis(server) == pid
  end

  test "provides a cluster-wide server reference" do
    assert PositionStore.clustered_server() ==
             {
               :via,
               Horde.Registry,
               {
                 Analysis.PositionStoreRegistry,
                 :position_store
               }
             }
  end

  test "appends and gets a position" do
    position = Position.starting_position()

    position_id = PositionStore.append(position)

    assert {:ok, ^position} = PositionStore.get(position_id)
  end

  test "returns not_found for an unknown position" do
    assert :not_found = PositionStore.get(999_999_999)
  end

  test "reuses the id of an existing position" do
    position = Position.starting_position()

    first_id = PositionStore.append(position)
    second_id = PositionStore.append(position)

    assert second_id == first_id
  end

  test "initializes from persistent storage" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "analysis-position-store-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    opts = [
      directory: directory,
      records_per_segment: 3,
      exact_bucket_count: 16,
      property_bucket_count: 16
    ]

    assert {
             :ok,
             %PositionStore.State{
               db: db
             }
           } =
             PositionStore.init(opts)

    position =
      Position.starting_position()

    {_db, position_id} =
      PositionDB.append(
        db,
        position
      )

    assert {
             :ok,
             %PositionStore.State{
               db: reopened
             }
           } =
             PositionStore.init(opts)

    assert PositionDB.get(
             reopened,
             position_id
           ) ==
             {:ok, position}

    assert PositionDB.find(
             reopened,
             position
           ) ==
             {:ok, position_id}
  end

  test "uses the cluster-wide server by default" do
    previous =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    on_exit(fn ->
      restore_position_store_config(previous)
    end)

    Application.delete_env(
      :analysis,
      PositionStore
    )

    assert PositionStore.server() ==
             PositionStore.clustered_server()
  end

  test "uses the configured server" do
    previous =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    on_exit(fn ->
      restore_position_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      PositionStore,
      server: :position_store_owner
    )

    assert PositionStore.server() == :position_store_owner
  end

  test "reports ready when the position store is reachable" do
    assert PositionStore.ready?()
  end

  test "reports not ready when the configured position store is unavailable" do
    previous =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    on_exit(fn ->
      restore_position_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      PositionStore,
      server: :unavailable_position_store
    )

    refute PositionStore.ready?()
  end

  test "reports not ready when the Horde registry is unavailable" do
    previous =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    on_exit(fn ->
      restore_position_store_config(previous)
    end)

    Application.put_env(
      :analysis,
      PositionStore,
      server: {
        :via,
        Horde.Registry,
        {
          :unavailable_position_store_registry,
          :position_store
        }
      }
    )

    refute PositionStore.ready?()
  end

  test "returns an empty page for a query with no matches" do
    assert PositionStore.query_page(
             Query.match_none(),
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
  end

  test "pages through a position query without duplicates or omissions" do
    use_isolated_position_store()

    position_1 =
      Position.starting_position()

    {:ok, position_2} =
      Position.apply_move(
        position_1,
        move("e2", "e4")
      )

    {:ok, position_3} =
      Position.apply_move(
        position_2,
        move("e7", "e5")
      )

    ids =
      Enum.map(
        [
          position_1,
          position_2,
          position_3
        ],
        &PositionStore.append/1
      )

    material =
      PositionProperties.material(position_1)

    query =
      Query.property(
        :material,
        material
      )

    assert {
             :ok,
             first_page,
             cursor
           } =
             PositionStore.query_page(
               query,
               2
             )

    assert is_reference(cursor)
    assert length(first_page) == 2

    assert {
             :ok,
             second_page,
             :done
           } =
             PositionStore.next_query_page(
               cursor,
               2
             )

    all_ids =
      first_page ++
        second_page

    assert length(all_ids) == 3

    assert MapSet.new(all_ids) ==
             MapSet.new(ids)

    assert PositionStore.next_query_page(
             cursor,
             2
           ) ==
             {:error, :cursor_not_found}
  end

  test "does not create a cursor when the first page exhausts the query" do
    use_isolated_position_store()

    id =
      PositionStore.append(Position.starting_position())

    assert {
             :ok,
             [^id],
             :done
           } =
             PositionStore.query_page(
               Query.match_all(),
               10
             )
  end

  test "closes an unfinished query cursor" do
    use_isolated_position_store()

    PositionStore.append(Position.starting_position())

    {:ok, second} =
      Position.apply_move(
        Position.starting_position(),
        move("e2", "e4")
      )

    PositionStore.append(second)

    assert {
             :ok,
             [_position_id],
             cursor
           } =
             PositionStore.query_page(
               Query.match_all(),
               1
             )

    assert :ok =
             PositionStore.close_query(cursor)

    assert PositionStore.next_query_page(
             cursor,
             1
           ) ==
             {:error, :cursor_not_found}
  end

  defp restore_position_store_config(:not_configured) do
    Application.delete_env(
      :analysis,
      PositionStore
    )
  end

  defp restore_position_store_config(value) do
    Application.put_env(
      :analysis,
      PositionStore,
      value
    )
  end

  defp use_isolated_position_store do
    previous =
      Application.get_env(
        :analysis,
        PositionStore,
        :not_configured
      )

    server =
      :"position-store-query-#{System.unique_integer([:positive])}"

    start_supervised!({PositionStore, server: server})

    Application.put_env(
      :analysis,
      PositionStore,
      server: server
    )

    on_exit(fn ->
      restore_position_store_config(previous)
    end)
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
