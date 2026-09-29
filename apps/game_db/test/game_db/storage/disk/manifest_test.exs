defmodule GameDB.Storage.Disk.ManifestTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.Manifest

  describe "encode/1 and decode/1" do
    test "round trips a storage manifest" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        canonical_bucket_count: 65_536,
        position_bucket_count: 131_072
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "supports large bucket counts" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        canonical_bucket_count: 4_294_967_296,
        position_bucket_count: 8_589_934_592
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "uses a version-independent file signature" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        canonical_bucket_count: 16,
        position_bucket_count: 32
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert <<
               "OCLGDB",
               0,
               0,
               1::unsigned-big-16,
               _rest::binary
             >> = encoded
    end

    test "rejects an invalid manifest magic" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        canonical_bucket_count: 16,
        position_bucket_count: 32
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      <<_first, rest::binary>> = encoded

      assert Manifest.decode(<<0, rest::binary>>) ==
               {:error, :invalid_manifest_magic}
    end

    test "rejects an unsupported manifest version" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        canonical_bucket_count: 16,
        position_bucket_count: 32
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
      assert Manifest.decode(<<"OCLGDB", 0, 0>>) ==
               {:error, :invalid_manifest}
    end

    test "rejects trailing bytes" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        canonical_bucket_count: 16,
        position_bucket_count: 32
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      <<
        magic::binary-size(8),
        version::unsigned-big-16,
        canonical_bucket_count::unsigned-big-64,
        position_bucket_count::unsigned-big-64,
        format_size::unsigned-big-32,
        format::binary
      >> = encoded

      assert Manifest.decode(<<
               magic::binary,
               version::unsigned-big-16,
               canonical_bucket_count::unsigned-big-64,
               position_bucket_count::unsigned-big-64,
               format_size::unsigned-big-32,
               format::binary,
               1
             >>) ==
               {:error, :invalid_manifest_size}
    end

    test "rejects invalid physical values when encoding" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        canonical_bucket_count: 0,
        position_bucket_count: 32
      }

      assert Manifest.encode(manifest) ==
               {:error, :invalid_manifest}
    end

    test "rejects an empty record format id" do
      manifest = %Manifest{
        record_format_id: <<>>,
        canonical_bucket_count: 16,
        position_bucket_count: 32
      }

      assert Manifest.encode(manifest) ==
               {:error, :invalid_manifest}
    end
  end
end
