defmodule DrValidator.ReportTest do
  use ExUnit.Case
  use ExUnitProperties

  alias DrValidator.{AppResult, Report}

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

  defp app_result_with_status_gen(status) do
    gen all name <- StreamData.string(:alphanumeric, min_length: 1) do
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

  # List of apps where all are :passed
  defp all_passed_gen do
    StreamData.list_of(app_result_with_status_gen(:passed), min_length: 1)
  end

  # List of apps that contains at least one :failed and no :partial
  defp has_failed_no_partial_gen do
    gen all failed <- StreamData.list_of(app_result_with_status_gen(:failed), min_length: 1),
            passed <- StreamData.list_of(app_result_with_status_gen(:passed)) do
      Enum.shuffle(failed ++ passed)
    end
  end

  # List of apps that contains at least one :partial (regardless of :failed)
  defp has_partial_gen do
    gen all partial <- StreamData.list_of(app_result_with_status_gen(:partial), min_length: 1),
            rest <- StreamData.list_of(app_result_gen()) do
      Enum.shuffle(partial ++ rest)
    end
  end

  # --- Properties ---

  property "overall_status is :passed iff all apps are :passed" do
    check all apps <- all_passed_gen() do
      report = Report.new(perimeter_id: "test", apps: apps)
      assert report.overall_status == :passed
    end
  end

  property "overall_status is :failed iff any app is :failed and none are :partial" do
    check all apps <- has_failed_no_partial_gen() do
      report = Report.new(perimeter_id: "test", apps: apps)
      assert report.overall_status == :failed
    end
  end

  property "overall_status is :partial iff any app is :partial" do
    check all apps <- has_partial_gen() do
      report = Report.new(perimeter_id: "test", apps: apps)
      assert report.overall_status == :partial
    end
  end

  property "JSON encode/decode round-trip preserves overall_status and perimeter_id" do
    check all apps <- StreamData.list_of(app_result_gen(), min_length: 1),
              perimeter_id <- StreamData.string(:alphanumeric, min_length: 1) do
      report = Report.new(perimeter_id: perimeter_id, apps: apps)
      json = Jason.encode!(report)
      decoded = Jason.decode!(json)
      assert decoded["overall_status"] == Atom.to_string(report.overall_status)
      assert decoded["perimeter_id"] == report.perimeter_id
      assert decoded["schema_version"] == report.schema_version
    end
  end
end
