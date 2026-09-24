defmodule PositionDB.Storage.PostingIndex.Disk.ManifestTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Manifest

  describe "encode/1 and decode/1" do
    test "round trips a posting-index manifest" do
      manifest =
        %Manifest{
          key_format_id: <<"chess-position-property-v1">>,
          bucket_count: 65_536
        }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "supports large bucket counts" do
      manifest =
        %Manifest{
          key_format_id: <<"property-v1">>,
          bucket_count: 4_294_967_296
        }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "rejects an invalid manifest magic" do
      manifest =
        %Manifest{
          key_format_id: <<"property-v1">>,
          bucket_count: 16
        }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      <<_first, rest::binary>> =
        encoded

      assert Manifest.decode(<<0, rest::binary>>) ==
               {:error, :invalid_posting_manifest_magic}
    end

    test "rejects an unsupported manifest version" do
      manifest =
        %Manifest{
          key_format_id: <<"property-v1">>,
          bucket_count: 16
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
               {:error, {:unsupported_posting_manifest_version, 2}}
    end

    test "rejects a truncated manifest" do
      assert Manifest.decode(<<"OCLPIX", 0, 0>>) ==
               {:error, :invalid_posting_manifest}
    end

    test "rejects trailing bytes" do
      manifest =
        %Manifest{
          key_format_id: <<"property-v1">>,
          bucket_count: 16
        }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(<<encoded::binary, 1>>) ==
               {:error, :invalid_posting_manifest_size}
    end

    test "rejects an empty key format id" do
      manifest =
        %Manifest{
          key_format_id: <<>>,
          bucket_count: 16
        }

      assert Manifest.encode(manifest) ==
               {:error, :invalid_posting_manifest}
    end

    test "rejects a zero bucket count" do
      manifest =
        %Manifest{
          key_format_id: <<"property-v1">>,
          bucket_count: 0
        }

      assert Manifest.encode(manifest) ==
               {:error, :invalid_posting_manifest}
    end

    test "uses a version-independent file signature" do
      manifest =
        %Manifest{
          key_format_id: <<"property-v1">>,
          bucket_count: 16
        }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert <<
               "OCLPIX",
               0,
               0,
               1::unsigned-big-16,
               _rest::binary
             >> = encoded
    end
  end
end
