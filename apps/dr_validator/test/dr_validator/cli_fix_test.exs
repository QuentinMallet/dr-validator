defmodule DrValidator.Test.FailingReportWriter do
  @moduledoc false
  def write(_report), do: {:error, :eacces}
  def write(_report, _path), do: {:error, :eacces}
end

defmodule DrValidator.Test.SuccessReportWriter do
  @moduledoc false
  def write(_report), do: :ok
  def write(_report, _path), do: :ok
end

defmodule DrValidator.CLIFixTest do
  @moduledoc """
  Tests for post-impl review fixes: escript exit code, ReportWriter error surface,
  arg validation, and unregistered-app warnings.
  """
  use ExUnit.Case, async: false
  use ExUnitProperties

  import ExUnit.CaptureIO

  alias DrValidator.CLI

  @wt Path.expand("../../../..", __DIR__)

  defp write_perimeters(perimeters) do
    path = Path.join(System.tmp_dir!(), "dr-test-#{System.unique_integer()}.json")
    File.write!(path, Jason.encode!(perimeters))
    path
  end

  defp rm(path), do: File.rm(path)

  defp with_report_writer(mod, fun) do
    original = Application.get_env(:dr_validator, :report_writer)

    Application.put_env(:dr_validator, :report_writer, mod)

    try do
      fun.()
    after
      if original,
        do: Application.put_env(:dr_validator, :report_writer, original),
        else: Application.delete_env(:dr_validator, :report_writer)
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 1 — escript exits with correct OS code
  # ---------------------------------------------------------------------------

  @tag :escript
  test "escript exits non-zero when perimeter not found" do
    escript = Path.join(@wt, "apps/dr_validator/dr-validator-run")
    tmp = write_perimeters([])

    {_out, rc} =
      System.cmd(escript, ["--perimeter", "nonexistent", "--perimeters-path", tmp],
        stderr_to_stdout: true
      )

    rm(tmp)
    assert rc != 0, "expected non-zero exit code from escript, got #{rc}"
  end

  @tag :escript
  test "escript exits 0 on --help" do
    escript = Path.join(@wt, "apps/dr_validator/dr-validator-run")
    {_out, rc} = System.cmd(escript, ["--help"], stderr_to_stdout: true)
    assert rc == 0
  end

  # ---------------------------------------------------------------------------
  # Fix 3 — ReportWriter error → exit code 3
  # ---------------------------------------------------------------------------

  describe "ReportWriter error handling" do
    test "returns exit code 3 when write returns {:error, reason}" do
      tmp = write_perimeters([%{"id" => "p1", "host" => "pi", "apps" => [], "canary" => false}])

      rc =
        with_report_writer(DrValidator.Test.FailingReportWriter, fn ->
          capture_io(:stderr, fn ->
            v = CLI.main(["--perimeter", "p1", "--perimeters-path", tmp])
            send(self(), {:rc, v})
          end)

          receive do
            {:rc, v} -> v
          end
        end)

      rm(tmp)
      assert rc == 3, "expected exit code 3, got #{rc}"
    end

    test "returns validator exit code when write succeeds" do
      tmp = write_perimeters([%{"id" => "p1", "host" => "pi", "apps" => [], "canary" => false}])

      rc =
        with_report_writer(DrValidator.Test.SuccessReportWriter, fn ->
          CLI.main(["--perimeter", "p1", "--perimeters-path", tmp])
        end)

      rm(tmp)
      assert rc in [0, 1, 2], "expected 0|1|2, got #{rc}"
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 4 — CLI arg validation: unknown options + non-positive timeout
  # ---------------------------------------------------------------------------

  describe "parse_args/1 — unknown options" do
    test "rejects unknown flag → {:error, :usage_error}" do
      assert CLI.parse_args(["--perimeter", "foo", "--bad-flag", "x"]) ==
               {:error, :usage_error}
    end

    test "--help takes precedence over unknown flags" do
      assert CLI.parse_args(["--help"]) == :help
    end
  end

  describe "parse_args/1 — non-positive timeout" do
    test "rejects zero" do
      assert CLI.parse_args(["--perimeter", "foo", "--app-timeout-ms", "0"]) ==
               {:error, :usage_error}
    end

    test "rejects negative" do
      assert CLI.parse_args(["--perimeter", "foo", "--app-timeout-ms", "-1"]) ==
               {:error, :usage_error}
    end

    test "accepts positive" do
      assert {:ok, %{app_timeout_ms: 9_999}} =
               CLI.parse_args(["--perimeter", "foo", "--app-timeout-ms", "9999"])
    end
  end

  property "non-positive integer timeout → :usage_error" do
    check all n <- integer(-100_000..0) do
      result = CLI.parse_args(["--perimeter", "x", "--app-timeout-ms", Integer.to_string(n)])
      assert result == {:error, :usage_error}
    end
  end

  describe "main/1 - exit 64 for validation failures" do
    test "zero timeout yields exit 64" do
      capture_io(:stderr, fn ->
        v = CLI.main(["--perimeter", "foo", "--app-timeout-ms", "0"])
        send(self(), {:rc, v})
      end)

      rc = receive do {:rc, v} -> v end
      assert rc == 64
    end

    test "unknown flag yields exit 64" do
      capture_io(:stderr, fn ->
        v = CLI.main(["--perimeter", "foo", "--no-such-opt", "x"])
        send(self(), {:rc, v})
      end)

      rc = receive do {:rc, v} -> v end
      assert rc == 64
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 6 — warn unregistered apps; include path in error messages
  # ---------------------------------------------------------------------------

  describe "unregistered apps warning" do
    test "logs unregistered app names to stderr" do
      tmp =
        write_perimeters([
          %{
            "id" => "p1",
            "host" => "pi",
            "apps" => ["zork_unregistered_7x9"],
            "canary" => false
          }
        ])

      stderr =
        with_report_writer(DrValidator.Test.SuccessReportWriter, fn ->
          capture_io(:stderr, fn ->
            _ = CLI.main(["--perimeter", "p1", "--perimeters-path", tmp])
          end)
        end)

      rm(tmp)
      assert stderr =~ "zork_unregistered_7x9", "expected app name in stderr, got: #{stderr}"
    end
  end

  describe "perimeters path in error messages" do
    test "file_not_found error includes the explicit path" do
      bad_path = "/tmp/dr_missing_#{System.unique_integer()}.json"

      stderr =
        capture_io(:stderr, fn ->
          _ = CLI.main(["--perimeter", "foo", "--perimeters-path", bad_path])
        end)

      assert stderr =~ bad_path, "expected path #{bad_path} in stderr, got: #{stderr}"
    end
  end
end
