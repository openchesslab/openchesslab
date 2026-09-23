defmodule PositionDB.Storage.Disk.ManifestTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.Manifest

  describe "encode/1 and decode/1" do
    test "round trips a storage manifest" do
      manifest = %Manifest{
        record_format_id: <<"chess-position-v1">>,
        record_size: 67,
        records_per_segment: 1_000_000,
        exact_hash_format_id: <<"sha256-v1">>,
        exact_hash_size: 32,
        exact_bucket_count: 65_536
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "supports large physical layout values" do
      manifest = %Manifest{
        record_format_id: <<"position-v1">>,
        record_size: 67,
        records_per_segment: 100_000_000,
        exact_hash_format_id: <<"hash-v1">>,
        exact_hash_size: 32,
        exact_bucket_count: 4_294_967_296
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "rejects an invalid manifest magic" do
      manifest = %Manifest{
        record_format_id: <<"position-v1">>,
        record_size: 67,
        records_per_segment: 1_000,
        exact_hash_format_id: <<"hash-v1">>,
        exact_hash_size: 32,
        exact_bucket_count: 16
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      <<_first, rest::binary>> = encoded

      assert Manifest.decode(<<0, rest::binary>>) ==
               {:error, :invalid_manifest_magic}
    end

    test "rejects an unsupported manifest version" do
      manifest = %Manifest{
        record_format_id: <<"position-v1">>,
        record_size: 67,
        records_per_segment: 1_000,
        exact_hash_format_id: <<"hash-v1">>,
        exact_hash_size: 32,
        exact_bucket_count: 16
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      <<
        magic::binary-size(8),
        _version::unsigned-big-16,
        rest::binary
      >> = encoded

      assert Manifest.decode(<<
               magic::binary,
               2::unsigned-big-16,
               rest::binary
             >>) ==
               {:error, {:unsupported_manifest_version, 2}}
    end

    test "rejects a truncated manifest" do
      assert Manifest.decode(<<"OCLPDB01">>) ==
               {:error, :invalid_manifest}
    end

    test "rejects trailing bytes" do
      manifest = %Manifest{
        record_format_id: <<"position-v1">>,
        record_size: 67,
        records_per_segment: 1_000,
        exact_hash_format_id: <<"hash-v1">>,
        exact_hash_size: 32,
        exact_bucket_count: 16
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(<<encoded::binary, 1>>) ==
               {:error, :invalid_manifest_size}
    end

    test "rejects invalid physical values when encoding" do
      manifest = %Manifest{
        record_format_id: <<"position-v1">>,
        record_size: 0,
        records_per_segment: 1_000,
        exact_hash_format_id: <<"hash-v1">>,
        exact_hash_size: 32,
        exact_bucket_count: 16
      }

      assert Manifest.encode(manifest) ==
               {:error, :invalid_manifest}
    end

    test "rejects empty format ids" do
      manifest = %Manifest{
        record_format_id: <<>>,
        record_size: 67,
        records_per_segment: 1_000,
        exact_hash_format_id: <<"hash-v1">>,
        exact_hash_size: 32,
        exact_bucket_count: 16
      }

      assert Manifest.encode(manifest) ==
               {:error, :invalid_manifest}
    end
  end
end
