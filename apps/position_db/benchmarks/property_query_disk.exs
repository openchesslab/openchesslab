alias PositionDB.PropertyIndex
alias PositionDB.PropertyIndex.Disk, as: PropertyIndexDisk
alias PositionDB.Query
alias PositionDB.QueryResult
alias PositionDB.Storage.PostingIndex.Disk.Entry
alias PositionDB.Storage.PostingIndex.Disk.Layout
alias PositionDB.Storage.PropertyKeyCodec

defmodule PositionDB.PropertyQueryDiskBenchmark.PropertyCodec do
  @moduledoc false

  @behaviour PropertyKeyCodec

  @impl PropertyKeyCodec
  def format_id do
    <<"property-query-benchmark-v1">>
  end

  @impl PropertyKeyCodec
  def encode(:selected, true) do
    {:ok, <<1>>}
  end

  def encode(_property, _value) do
    {:error, :unsupported_property}
  end
end

defmodule PositionDB.PropertyQueryDiskBenchmark do
  @moduledoc false

  alias __MODULE__.PropertyCodec
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndex.Disk, as: PropertyIndexDisk
  alias PositionDB.Storage.PostingIndex.Disk.Entry
  alias PositionDB.Storage.PostingIndex.Disk.Layout

  @chunk_size 10_000

  def build(posting_count) do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-property-query-benchmark-#{System.unique_integer([:positive])}"
      )

    directory =
      Path.join(
        root,
        "property-index"
      )

    File.mkdir_p!(root)

    {:ok, backend} =
      PropertyIndexDisk.create(
        directory,
        codec: PropertyCodec,
        bucket_count: 1
      )

    {:ok, key} =
      PropertyCodec.encode(
        :selected,
        true
      )

    bucket_path =
      Layout.bucket_path(
        directory,
        0
      )

    write_postings(
      bucket_path,
      key,
      posting_count
    )

    {:ok, backend} =
      PropertyIndexDisk.advance(
        backend,
        posting_count
      )

    index =
      PropertyIndex.new(
        PropertyIndexDisk,
        backend
      )

    db =
      PositionDB.new(
        key_function: & &1,
        properties: [],
        property_index: index
      )

    %{
      root: root,
      bucket_path: bucket_path,
      db: db,
      index: index
    }
  end

  defp write_postings(path, key, posting_count) do
    File.open!(
      path,
      [
        :write,
        :binary
      ],
      fn file ->
        1..posting_count
        |> Stream.chunk_every(@chunk_size)
        |> Enum.each(fn position_ids ->
          entries =
            Enum.map(
              position_ids,
              &Entry.encode(
                key,
                &1
              )
            )

          :ok =
            IO.binwrite(
              file,
              entries
            )
        end)
      end
    )
  end
end

posting_count =
  System.get_env(
    "POSITION_DB_BENCH_POSTINGS",
    "100000"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "POSITION_DB_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise "POSITION_DB_BENCH_POSTINGS must be positive"
end

if page_size <= 0 do
  raise "POSITION_DB_BENCH_PAGE_SIZE must be positive"
end

fixture =
  PositionDB.PropertyQueryDiskBenchmark.build(posting_count)

query =
  Query.property(
    :selected,
    true
  )

expected_page_size =
  min(
    posting_count,
    page_size
  )

bucket_size =
  File.stat!(fixture.bucket_path).size

IO.puts("""
PositionDB disk property-query benchmark

postings:    #{posting_count}
page size:   #{page_size}
bucket size: #{bucket_size} bytes
""")

try do
  Benchee.run(
    %{
      "property query: first result" => fn ->
        result =
          PositionDB.query(
            fixture.db,
            query
          )

        case QueryResult.next(result) do
          {
            :ok,
            1,
            _result
          } ->
            :ok

          other ->
            raise "unexpected first result: #{inspect(other)}"
        end
      end,
      "property query: first page" => fn ->
        position_ids =
          fixture.db
          |> PositionDB.query(query)
          |> Enum.take(page_size)

        if length(position_ids) !=
             expected_page_size do
          raise """
          expected #{expected_page_size} positions, got #{length(position_ids)}
          """
        end

        position_ids
      end,
      "property cardinality" => fn ->
        case PropertyIndex.cardinality_result(
               fixture.index,
               {
                 :selected,
                 true
               }
             ) do
          {:ok, ^posting_count} ->
            :ok

          other ->
            raise "unexpected cardinality: #{inspect(other)}"
        end
      end
    },
    warmup: 1,
    time: 3,
    memory_time: 2,
    parallel: 1
  )
after
  File.rm_rf!(fixture.root)
end
