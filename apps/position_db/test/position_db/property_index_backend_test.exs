defmodule PositionDB.PropertyIndexBackendTest do
  use ExUnit.Case, async: true

  alias PositionDB.EquivalenceContext
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndex.Disk
  alias PositionDB.Query
  alias PositionDB.QueryEngine
  alias PositionDB.QueryExecutionError
  alias PositionDB.PositionStore

  defmodule TestCodec do
    @behaviour PositionDB.Storage.PropertyKeyCodec

    @impl PositionDB.Storage.PropertyKeyCodec
    def format_id do
      <<"query-property-v1">>
    end

    @impl PositionDB.Storage.PropertyKeyCodec
    def encode(
          :color,
          :white
        ) do
      {:ok, <<1, 1>>}
    end

    def encode(
          :color,
          :black
        ) do
      {:ok, <<1, 2>>}
    end

    def encode(
          _property,
          _value
        ) do
      {:error, :unsupported_property}
    end
  end

  defmodule FailingBackend do
    @behaviour PositionDB.PropertyIndex.Backend

    @impl PositionDB.PropertyIndex.Backend
    def add(
          _backend,
          _property,
          _position_id
        ) do
      {:error, :disk_failure}
    end

    @impl PositionDB.PropertyIndex.Backend
    def lookup(
          _backend,
          _property
        ) do
      {:error, :disk_failure}
    end

    @impl PositionDB.PropertyIndex.Backend
    def cardinality(
          _backend,
          _property
        ) do
      {:error, :disk_failure}
    end
  end

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-property-backend-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory
    }
  end

  test "executes a property query through the disk backend", %{
    directory: directory
  } do
    assert {:ok, disk} =
             Disk.create(
               directory,
               codec: TestCodec,
               bucket_count: 1
             )

    assert {:ok, disk} =
             Disk.add(
               disk,
               {:color, :white},
               1
             )

    assert {:ok, disk} =
             Disk.add(
               disk,
               {:color, :white},
               2
             )

    assert {:ok, disk} =
             Disk.add(
               disk,
               {:color, :black},
               3
             )

    assert {:ok, disk} =
             Disk.advance(
               disk,
               3
             )

    index =
      PropertyIndex.new(
        Disk,
        disk
      )

    store =
      store_with_ids([1, 2, 3])

    result =
      QueryEngine.execute(
        index,
        store,
        Query.property(
          :color,
          :white
        ),
        equivalence_context()
      )

    assert Enum.to_list(result) ==
             [1, 2]
  end

  test "propagates a lazy property lookup failure" do
    index =
      PropertyIndex.new(
        FailingBackend,
        :backend
      )

    result =
      QueryEngine.execute(
        index,
        store_with_ids([1]),
        Query.property(
          :color,
          :white
        ),
        equivalence_context()
      )

    assert_raise QueryExecutionError,
                 "query execution failed: :disk_failure",
                 fn ->
                   Enum.to_list(result)
                 end
  end

  test "propagates a property cardinality failure during AND planning" do
    index =
      PropertyIndex.new(
        FailingBackend,
        :backend
      )

    query =
      Query.all([
        Query.property(
          :color,
          :white
        ),
        Query.property(
          :color,
          :black
        )
      ])

    result =
      QueryEngine.execute(
        index,
        store_with_ids([1, 2]),
        query,
        equivalence_context()
      )

    assert_raise QueryExecutionError,
                 "query execution failed: :disk_failure",
                 fn ->
                   Enum.to_list(result)
                 end
  end

  test "propagates a property lookup failure through NOT" do
    index =
      PropertyIndex.new(
        FailingBackend,
        :backend
      )

    query =
      Query.negate(
        Query.property(
          :color,
          :white
        )
      )

    result =
      QueryEngine.execute(
        index,
        store_with_ids([1, 2]),
        query,
        equivalence_context()
      )

    assert_raise QueryExecutionError,
                 "query execution failed: :disk_failure",
                 fn ->
                   Enum.to_list(result)
                 end
  end

  defp store_with_ids(ids) do
    Enum.reduce(
      ids,
      PositionStore.new(& &1),
      fn id, store ->
        {:ok, store, _position_id} =
          PositionStore.put(
            store,
            id
          )

        store
      end
    )
  end

  defp equivalence_context do
    EquivalenceContext.new(
      & &1,
      &(&1 == &2)
    )
  end
end
