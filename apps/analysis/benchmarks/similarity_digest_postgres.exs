# Similarity-digest search benchmark: narrowing strategies and score ranking
# for "find similar positions" over a fixture copied from the development
# corpus (real lichess-game distribution, ~400k positions).
#
# Benchmark-only: it creates and drops its own `bench_*` tables in the
# disposable benchmark database and never touches production schema.
#
# Run from the umbrella root:
#
#   DATABASE_URL=ecto://openchesslab:openchesslab@localhost/openchesslab_bench \
#     mix run apps/analysis/benchmarks/similarity_digest_postgres.exs
#
# Optional: SIMILARITY_BENCH_DEV_URL overrides the read side (default: the
# local development database). SIMILARITY_BENCH_FULL_PLAN=1 prints full plans.

alias Analysis.PositionSimilarity
alias Chess.PositionCodec
alias OpenChessLab.Repo

Logger.configure(level: :warning)

Application.ensure_all_started(:database)

defmodule SimilarityDigestBenchmark do
  @moduledoc false

  @batch 2_000

  def build_fixture(dev_url) do
    Repo.query!("DROP TABLE IF EXISTS bench_digests, bench_positions", [])

    Repo.query!(
      """
      CREATE TABLE bench_positions (
        id bigint PRIMARY KEY,
        record bytea NOT NULL,
        white_pawns bigint NOT NULL,
        black_pawns bigint NOT NULL
      )
      """,
      []
    )

    Repo.query!(
      """
      CREATE TABLE bench_digests (
        position_id bigint PRIMARY KEY REFERENCES bench_positions(id),
        side_to_move boolean NOT NULL,
        castling smallint NOT NULL,
        material_key bigint NOT NULL,
        king_key integer NOT NULL,
        open_files smallint NOT NULL,
        semi_open_white smallint NOT NULL,
        semi_open_black smallint NOT NULL
      )
      """,
      []
    )

    {:ok, dev} = connect(dev_url)

    {:ok, %{num_rows: total}} = Postgrex.query(dev, "SELECT count(*) FROM positions", [])

    IO.puts("copying and digesting #{total} development positions...")

    {microseconds, position_count} =
      :timer.tc(fn ->
        Postgrex.transaction(dev, fn conn ->
          Postgrex.stream(conn, "SELECT id, record, white_pawns, black_pawns FROM positions", [],
            max_rows: @batch
          )
          |> Stream.map(& &1.rows)
          |> Enum.reduce(0, fn rows, count ->
            {positions, digests} =
              rows
              |> Enum.map(fn [id, record, white_pawns, black_pawns] ->
                {:ok, position} = PositionCodec.decode(record)
                digest = PositionSimilarity.digest(position)

                {
                  %{id: id, record: record, white_pawns: white_pawns, black_pawns: black_pawns},
                  %{
                    position_id: id,
                    side_to_move: digest.side_to_move == :white,
                    castling: digest.castling,
                    material_key: digest.material_key,
                    king_key: digest.king_key,
                    open_files: digest.open_files,
                    semi_open_white: digest.semi_open_white,
                    semi_open_black: digest.semi_open_black
                  }
                }
              end)
              |> Enum.unzip()

            Repo.insert_all("bench_positions", positions)
            Repo.insert_all("bench_digests", digests)

            count + length(rows)
          end)
        end)
        |> then(fn {:ok, count} -> count end)
      end)

    Repo.query!(
      "CREATE INDEX bench_positions_pawns ON bench_positions (white_pawns, black_pawns)",
      []
    )

    Repo.query!("CREATE INDEX bench_digests_material ON bench_digests (material_key)", [])
    Repo.query!("ANALYZE bench_positions", [])
    Repo.query!("ANALYZE bench_digests", [])

    rate = round(position_count * 1_000_000 / microseconds)

    IO.puts(
      "fixture: #{position_count} positions in #{div(microseconds, 1000)} ms (#{rate}/s incl. decode + digest)"
    )
  end

  # Postgrex takes keyword options, not an ecto:// URL.
  defp connect(url) do
    uri = URI.parse(url)
    [user, password] = String.split(uri.userinfo || "openchesslab:openchesslab", ":")

    Postgrex.start_link(
      hostname: uri.host || "localhost",
      username: user,
      password: password,
      database: String.trim_leading(uri.path || "/openchesslab_dev", "/")
    )
  end

  def distribution do
    %{rows: [[distinct_materials, distinct_structures]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(DISTINCT material_key) FROM bench_digests),
          (SELECT count(DISTINCT (white_pawns, black_pawns)) FROM bench_positions)
        """,
        []
      )

    %{rows: top_structures} =
      Repo.query!(
        """
        SELECT count(*) AS n
        FROM bench_positions
        GROUP BY white_pawns, black_pawns
        ORDER BY n DESC
        LIMIT 5
        """,
        []
      )

    %{rows: top_materials} =
      Repo.query!(
        """
        SELECT count(*) AS n
        FROM bench_digests
        GROUP BY material_key
        ORDER BY n DESC
        LIMIT 5
        """,
        []
      )

    IO.puts("""
    distribution:
      distinct material keys:  #{distinct_materials}
      distinct structures:     #{distinct_structures}
      top structure sizes:     #{inspect(Enum.map(top_structures, &hd/1))}
      top material key sizes:  #{inspect(Enum.map(top_materials, &hd/1))}
    """)
  end

  def query_variants(sample) do
    variants = [
      %{
        name: "structure+material",
        count_sql:
          "SELECT count(*) FROM bench_positions p JOIN bench_digests sd ON sd.position_id = p.id WHERE p.white_pawns = $1 AND p.black_pawns = $2 AND sd.material_key = $3",
        count_params: [sample.white_pawns, sample.black_pawns, sample.material_key],
        sql: """
          SELECT p.id
          FROM bench_positions p
          JOIN bench_digests sd ON sd.position_id = p.id
          WHERE p.white_pawns = $1 AND p.black_pawns = $2 AND sd.material_key = $3
          ORDER BY p.id
          LIMIT 24
        """,
        params: [sample.white_pawns, sample.black_pawns, sample.material_key]
      },
      %{
        name: "material-only",
        count_sql: "SELECT count(*) FROM bench_digests sd WHERE sd.material_key = $1",
        count_params: [sample.material_key],
        sql: """
          SELECT sd.position_id
          FROM bench_digests sd
          WHERE sd.material_key = $1
          ORDER BY sd.position_id
          LIMIT 24
        """,
        params: [sample.material_key]
      },
      %{
        name: "ranked",
        count_sql:
          "SELECT count(*) FROM bench_positions p JOIN bench_digests sd ON sd.position_id = p.id WHERE p.white_pawns = $1 AND p.black_pawns = $2 AND sd.material_key = $3",
        count_params: [sample.white_pawns, sample.black_pawns, sample.material_key],
        sql: """
          SELECT
            p.id,
            (CASE WHEN sd.side_to_move = $4 THEN 2 ELSE 0 END
             + CASE WHEN sd.castling = $5 THEN 1 ELSE 0 END
             + CASE WHEN sd.king_key = $6 THEN 2 ELSE 0 END
             + bit_count(((sd.open_files & $7)::int)::bit(8))
             + bit_count(((sd.semi_open_white & $8)::int)::bit(8))
             + bit_count(((sd.semi_open_black & $9)::int)::bit(8))) AS score
          FROM bench_positions p
          JOIN bench_digests sd ON sd.position_id = p.id
          WHERE p.white_pawns = $1 AND p.black_pawns = $2 AND sd.material_key = $3
          ORDER BY score DESC, p.id
          LIMIT 24
        """,
        params: [
          sample.white_pawns,
          sample.black_pawns,
          sample.material_key,
          sample.side_to_move == :white,
          sample.castling,
          sample.king_key,
          sample.open_files,
          sample.semi_open_white,
          sample.semi_open_black
        ]
      }
    ]

    for variant <- variants do
      %{rows: [[candidates]]} = Repo.query!(variant.count_sql, variant.count_params)

      %{rows: plan_rows} =
        Repo.query!("EXPLAIN (ANALYZE, BUFFERS) #{variant.sql}", variant.params)

      print_plan(variant.name, candidates, plan_rows)
    end
  end

  defp print_plan(name, candidates, plan_rows) do
    text = Enum.map_join(plan_rows, "\n", &hd/1)

    timing =
      case Regex.run(~r/Execution Time: ([0-9.]+) ms/, text) do
        [_, time] -> time
        _ -> "?"
      end

    buffers =
      case Regex.run(~r/shared hit=(\d+)/, text) do
        [_, hit] -> hit
        _ -> "0"
      end

    plan_line = text |> String.split("\n") |> List.first()

    IO.puts("""
    #{name}: #{candidates} candidate(s)
      execution: #{timing} ms, shared hits: #{buffers}
      plan: #{plan_line}
    """)

    if System.get_env("SIMILARITY_BENCH_FULL_PLAN") == "1" do
      IO.puts(text <> "\n")
    end
  end

  def sample_at(description, offset) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          p.id,
          p.white_pawns,
          p.black_pawns,
          sd.side_to_move,
          sd.castling,
          sd.material_key,
          sd.king_key,
          sd.open_files,
          sd.semi_open_white,
          sd.semi_open_black
        FROM bench_positions p
        JOIN bench_digests sd ON sd.position_id = p.id
        ORDER BY p.id
        OFFSET $1
        LIMIT 1
        """,
        [offset]
      )

    [
      id,
      white_pawns,
      black_pawns,
      side_to_move,
      castling,
      material_key,
      king_key,
      open_files,
      semi_open_white,
      semi_open_black
    ] = List.first(rows) || raise("no sample at offset #{offset}")

    IO.puts(
      "sample #{description}: position #{id} (material #{material_key}, castling #{castling})"
    )

    %{
      id: id,
      white_pawns: white_pawns,
      black_pawns: black_pawns,
      side_to_move: side_to_move,
      castling: castling,
      material_key: material_key,
      king_key: king_key,
      open_files: open_files,
      semi_open_white: semi_open_white,
      semi_open_black: semi_open_black
    }
  end
end

_database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required (benchmark database — the fixture tables are
    dropped and recreated there).
    """

dev_url =
  System.get_env("SIMILARITY_BENCH_DEV_URL") ||
    "postgres://openchesslab:openchesslab@localhost/openchesslab_dev"

SimilarityDigestBenchmark.build_fixture(dev_url)
SimilarityDigestBenchmark.distribution()

for {description, offset} <- [
      {"early in the corpus", 9},
      {"middle of the corpus", 200_000},
      {"late in the corpus", 390_000}
    ] do
  sample = SimilarityDigestBenchmark.sample_at(description, offset)
  IO.puts("")
  SimilarityDigestBenchmark.query_variants(sample)
end

IO.puts("(set SIMILARITY_BENCH_FULL_PLAN=1 for full EXPLAIN output)")
