defmodule DrValidator.PerimeterLoaderTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DrValidator.PerimeterLoader
  alias DrValidator.Perimeter

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  defp gen_id, do: StreamData.string(:alphanumeric, min_length: 1, max_length: 20)

  defp gen_host do
    StreamData.member_of(["pi", "silver", "boatmurdered", "yellow", "webhost"])
  end

  defp gen_app_name, do: StreamData.string(:alphanumeric, min_length: 1, max_length: 15)

  defp gen_apps, do: StreamData.list_of(gen_app_name(), min_length: 1, max_length: 5)

  defp gen_valid_perimeter do
    gen all id <- gen_id(),
            host <- gen_host(),
            apps <- gen_apps(),
            canary <- StreamData.boolean(),
            archive_age_days_max <-
              StreamData.one_of([
                StreamData.constant(nil),
                StreamData.integer(1..365)
              ]) do
      base = %{"id" => id, "host" => host, "apps" => apps, "canary" => canary}

      if archive_age_days_max do
        Map.put(base, "archiveAgeDaysMax", archive_age_days_max)
      else
        base
      end
    end
  end

  defp gen_valid_perimeters do
    StreamData.list_of(gen_valid_perimeter(), min_length: 1, max_length: 5)
  end

  # Generators for malformed input: entries missing required keys or wrong types
  defp gen_missing_key_perimeter do
    gen all valid <- gen_valid_perimeter(),
            key_to_drop <- StreamData.member_of(["id", "host", "apps", "canary"]) do
      Map.delete(valid, key_to_drop)
    end
  end

  defp gen_wrong_type_perimeter do
    gen all valid <- gen_valid_perimeter(),
            field <- StreamData.member_of([:id_wrong, :host_wrong, :apps_wrong, :canary_wrong]) do
      case field do
        :id_wrong -> Map.put(valid, "id", 42)
        :host_wrong -> Map.put(valid, "host", true)
        :apps_wrong -> Map.put(valid, "apps", "not-a-list")
        :canary_wrong -> Map.put(valid, "canary", "yes")
      end
    end
  end

  defp gen_malformed_perimeter do
    StreamData.one_of([gen_missing_key_perimeter(), gen_wrong_type_perimeter()])
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_tmp_file(data) do
    path = System.tmp_dir!() |> Path.join("perimeter_test_#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(data))
    on_exit(fn -> File.rm(path) end)
    path
  end

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  property "valid perimeter JSON round-trips through PerimeterLoader.list/1" do
    check all perimeters <- gen_valid_perimeters() do
      path = write_tmp_file(perimeters)
      assert {:ok, parsed} = PerimeterLoader.list(path)
      assert length(parsed) == length(perimeters)
      assert Enum.all?(parsed, &match?(%Perimeter{}, &1))
    end
  end

  property "each parsed perimeter has required fields" do
    check all perimeters <- gen_valid_perimeters() do
      path = write_tmp_file(perimeters)
      {:ok, parsed} = PerimeterLoader.list(path)

      for {p, raw} <- Enum.zip(parsed, perimeters) do
        assert p.id == raw["id"]
        assert p.host == raw["host"]
        assert p.apps == raw["apps"]
        assert p.canary == raw["canary"]
        assert p.archive_age_days_max == raw["archiveAgeDaysMax"]
      end
    end
  end

  property "list with any malformed entry returns {:error, :malformed}" do
    check all valid <- gen_valid_perimeters(),
              bad <- gen_malformed_perimeter() do
      # Insert bad entry at a random position
      idx = rem(System.unique_integer([:positive]), length(valid) + 1)
      {before, after_} = Enum.split(valid, idx)
      data = before ++ [bad] ++ after_
      path = write_tmp_file(data)
      assert {:error, :malformed} = PerimeterLoader.list(path)
    end
  end

  property "get/2 finds perimeter by id when present" do
    check all perimeters <- gen_valid_perimeters(),
              target <- StreamData.member_of(perimeters) do
      path = write_tmp_file(perimeters)
      assert {:ok, found} = PerimeterLoader.get(path, target["id"])
      assert found.id == target["id"]
      assert found.host == target["host"]
    end
  end

  property "get/2 returns {:error, :not_found} for unknown id" do
    check all perimeters <- gen_valid_perimeters(),
              unknown_id <- StreamData.string(:alphanumeric, min_length: 30) do
      # Highly unlikely to collide with generated ids (max 20 chars)
      path = write_tmp_file(perimeters)
      assert {:error, :not_found} = PerimeterLoader.get(path, unknown_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests
  # ---------------------------------------------------------------------------

  test "list/1 returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} = PerimeterLoader.list("/nonexistent/path/perimeters.json")
  end

  test "list/1 returns {:error, :malformed} for invalid JSON" do
    # write_tmp_file uses Jason.encode! so we need to write raw bytes directly
    raw_path =
      System.tmp_dir!()
      |> Path.join("perimeter_raw_#{System.unique_integer([:positive])}.json")
    File.write!(raw_path, "{ not: valid json ]")
    on_exit(fn -> File.rm(raw_path) end)
    assert {:error, :malformed} = PerimeterLoader.list(raw_path)
  end

  test "list/1 returns {:error, :malformed} when JSON is not a list" do
    path = write_tmp_file(%{"id" => "pi-full"})
    assert {:error, :malformed} = PerimeterLoader.list(path)
  end

  test "list/1 returns {:error, :malformed} for entry missing 'id'" do
    path = write_tmp_file([%{"host" => "pi", "apps" => ["openbao"], "canary" => true}])
    assert {:error, :malformed} = PerimeterLoader.list(path)
  end

  test "list/1 returns {:error, :malformed} for entry missing 'host'" do
    path = write_tmp_file([%{"id" => "pi-full", "apps" => ["openbao"], "canary" => true}])
    assert {:error, :malformed} = PerimeterLoader.list(path)
  end

  test "list/1 returns {:error, :malformed} for entry where apps is not a list" do
    path = write_tmp_file([%{"id" => "pi-full", "host" => "pi", "apps" => "openbao", "canary" => true}])
    assert {:error, :malformed} = PerimeterLoader.list(path)
  end

  test "list/1 parses archiveAgeDaysMax as optional" do
    data = [%{"id" => "pi-full", "host" => "pi", "apps" => ["openbao"], "canary" => true}]
    path = write_tmp_file(data)
    assert {:ok, [p]} = PerimeterLoader.list(path)
    assert p.archive_age_days_max == nil
  end

  test "list/1 parses archiveAgeDaysMax when present" do
    data = [%{"id" => "pi-full", "host" => "pi", "apps" => ["openbao"], "canary" => false, "archiveAgeDaysMax" => 30}]
    path = write_tmp_file(data)
    assert {:ok, [p]} = PerimeterLoader.list(path)
    assert p.archive_age_days_max == 30
  end

  test "get/2 returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} = PerimeterLoader.get("/nonexistent.json", "pi-full")
  end

  # ---------------------------------------------------------------------------
  # Fix 5 — PerimeterLoader distinguishes error variants
  # ---------------------------------------------------------------------------

  describe "Fix 5: error variant :permission_denied" do
    @tag :unix_permissions
    test "unreadable file → {:error, :permission_denied}" do
      path = "/tmp/dr-noperm-#{System.unique_integer()}.json"
      File.write!(path, "[]")
      File.chmod!(path, 0o000)

      result =
        try do
          PerimeterLoader.list(path)
        after
          File.chmod!(path, 0o644)
          File.rm!(path)
        end

      assert result == {:error, :permission_denied}
    end

    @tag :unix_permissions
    test "unreadable file propagates through get/2" do
      path = "/tmp/dr-noperm-get-#{System.unique_integer()}.json"
      File.write!(path, "[]")
      File.chmod!(path, 0o000)

      result =
        try do
          PerimeterLoader.get(path, "any")
        after
          File.chmod!(path, 0o644)
          File.rm!(path)
        end

      assert result == {:error, :permission_denied}
    end
  end

  describe "Fix 5: error variant {:file_error, reason}" do
    test "reading a directory path → {:error, {:file_error, _}}" do
      dir = "/tmp/dr-dir-#{System.unique_integer()}"
      File.mkdir_p!(dir)

      result =
        try do
          PerimeterLoader.list(dir)
        after
          File.rmdir(dir)
        end

      assert match?({:error, {:file_error, _}}, result),
             "expected {:error, {:file_error, _}}, got #{inspect(result)}"
    end
  end

  test "list/0 uses DR_PERIMETERS_PATH env var" do
    data = [%{"id" => "env-test", "host" => "pi", "apps" => ["openbao"], "canary" => true}]
    path = write_tmp_file(data)
    System.put_env("DR_PERIMETERS_PATH", path)
    on_exit(fn -> System.delete_env("DR_PERIMETERS_PATH") end)
    assert {:ok, [p]} = PerimeterLoader.list()
    assert p.id == "env-test"
  end
end
