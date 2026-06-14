defmodule DrValidator.ReportWriterTest do
  use ExUnit.Case
  use ExUnitProperties

  alias DrValidator.{AppResult, Report, ReportWriter}

  # --- Generators ---

  defp status_gen, do: StreamData.member_of([:passed, :failed, :partial])

  defp app_result_gen do
    gen all name <- StreamData.string(:alphanumeric, min_length: 1),
            status <- status_gen() do
      %AppResult{
        name: name,
        status: status,
        duration_ms: 0,
        started_at: nil,
        completed_at: nil,
        error_message: nil,
        details: %{}
      }
    end
  end

  defp datetime_gen do
    gen all unix <- StreamData.integer(0..2_000_000_000) do
      DateTime.from_unix!(unix)
    end
  end

  defp report_gen do
    gen all perimeter_id <- StreamData.string(:alphanumeric, min_length: 1),
            apps <- StreamData.list_of(app_result_gen(), min_length: 1),
            started_at <- datetime_gen(),
            completed_at <- datetime_gen() do
      Report.new(
        perimeter_id: perimeter_id,
        apps: apps,
        started_at: started_at,
        completed_at: completed_at
      )
    end
  end

  # --- Properties ---

  property "round-trip: write then read back parses to equivalent report" do
    check all report <- report_gen() do
      dir = System.tmp_dir!()
      path = Path.join(dir, "report-#{:erlang.unique_integer([:positive])}.json")

      try do
        assert :ok = ReportWriter.write(report, path)
        assert File.exists?(path)

        decoded = path |> File.read!() |> Jason.decode!(keys: :strings)

        assert decoded["perimeter_id"] == report.perimeter_id
        assert decoded["schema_version"] == report.schema_version
        assert decoded["overall_status"] == Atom.to_string(report.overall_status)
        assert length(decoded["apps"]) == length(report.apps)
      after
        File.rm(path)
      end
    end
  end

  property "deterministic output: two writes of the same report produce identical bytes" do
    check all report <- report_gen() do
      dir = System.tmp_dir!()
      path1 = Path.join(dir, "report-a-#{:erlang.unique_integer([:positive])}.json")
      path2 = Path.join(dir, "report-b-#{:erlang.unique_integer([:positive])}.json")

      try do
        assert :ok = ReportWriter.write(report, path1)
        assert :ok = ReportWriter.write(report, path2)
        assert File.read!(path1) == File.read!(path2)
      after
        File.rm(path1)
        File.rm(path2)
      end
    end
  end

  property "apps sorted by name in output JSON" do
    check all apps <- StreamData.list_of(app_result_gen(), min_length: 2),
              perimeter_id <- StreamData.string(:alphanumeric, min_length: 1) do
      report = Report.new(perimeter_id: perimeter_id, apps: apps)
      dir = System.tmp_dir!()
      path = Path.join(dir, "report-sorted-#{:erlang.unique_integer([:positive])}.json")

      try do
        assert :ok = ReportWriter.write(report, path)
        decoded = path |> File.read!() |> Jason.decode!(keys: :strings)
        written_names = Enum.map(decoded["apps"], & &1["name"])
        assert written_names == Enum.sort(written_names)
      after
        File.rm(path)
      end
    end
  end

  test "write creates parent directories if they don't exist" do
    dir = Path.join(System.tmp_dir!(), "dr-test-#{:erlang.unique_integer([:positive])}")
    path = Path.join(dir, "nested/report.json")
    report = Report.new(perimeter_id: "p1", apps: [%AppResult{name: "a", status: :passed}])

    try do
      assert :ok = ReportWriter.write(report, path)
      assert File.exists?(path)
    after
      File.rm_rf(dir)
    end
  end

  test "write returns error tuple on unwritable path" do
    path = "/proc/noaccess/report.json"
    report = Report.new(perimeter_id: "p1", apps: [%AppResult{name: "a", status: :passed}])
    result = ReportWriter.write(report, path)
    assert match?({:error, _}, result)
  end
end
