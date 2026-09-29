defmodule GameDB.Storage.Disk.ManifestTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.Manifest

  describe "encode/1 and decode/1" do
    test "round trips a storage manifest" do
      manifest = manifest()

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "supports large physical layout values" do
      manifest = %Manifest{
        record_format_id: <<"game-v1">>,
        fingerprint_format_id: <<"game-sha256-v1">>,
        fingerprint_size: 32,
        canonical_bucket_count: 4_294_967_296,
        position_bucket_count: 8_589_934_592
      }

      assert {:ok, encoded} =
               Manifest.encode(manifest)

      assert Manifest.decode(encoded) ==
               {:ok, manifest}
    end

    test "uses a version-independent file signature" do
      assert {:ok, encoded} =
               manifest()
               |> Manifest.encode()

      assert <<
               "OCLGDB",
               0,
               0,
               1::unsigned-big-16,
               _rest::binary
             >> = encoded
    end

    test "rejects an invalid manifest magic" do
      assert {:ok, encoded} =
               manifest()
               |> Manifest.encode()

      <<_first, rest::binary>> = encoded

      assert Manifest.decode(<<0, rest::binary>>) ==
               {:error, :invalid_manifest_magic}
    end

    test "rejects an unsupported manifest version" do
      assert {:ok, encoded} =
               manifest()
               |> Manifest.encode()

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
      assert {:ok, encoded} =
               manifest()
               |> Manifest.encode()

      assert Manifest.decode(<<encoded::binary, 1>>) ==
               {:error, :invalid_manifest_size}
    end

    test "rejects an invalid canonical bucket count" do
      invalid =
        %{
          manifest()
          | canonical_bucket_count: 0
        }

      assert Manifest.encode(invalid) ==
               {:error, :invalid_manifest}
    end

    test "rejects an invalid position bucket count" do
      invalid =
        %{
          manifest()
          | position_bucket_count: 0
        }

      assert Manifest.encode(invalid) ==
               {:error, :invalid_manifest}
    end

    test "rejects an empty record format id" do
      invalid =
        %{
          manifest()
          | record_format_id: <<>>
        }

      assert Manifest.encode(invalid) ==
               {:error, :invalid_manifest}
    end

    test "rejects an empty fingerprint format id" do
      invalid =
        %{
          manifest()
          | fingerprint_format_id: <<>>
        }

      assert Manifest.encode(invalid) ==
               {:error, :invalid_manifest}
    end

    test "rejects an invalid fingerprint size" do
      invalid =
        %{
          manifest()
          | fingerprint_size: 0
        }

      assert Manifest.encode(invalid) ==
               {:error, :invalid_manifest}
    end
  end

  defp manifest do
    %Manifest{
      record_format_id: <<"game-v1">>,
      fingerprint_format_id: <<"game-sha256-v1">>,
      fingerprint_size: 32,
      canonical_bucket_count: 65_536,
      position_bucket_count: 131_072
    }
  end
end
