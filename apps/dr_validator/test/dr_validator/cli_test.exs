defmodule DrValidator.CLITest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DrValidator.CLI

  # ---------------------------------------------------------------------------
  # Static mock validators (defined once — avoids per-iteration compilation in PBT)
  # ---------------------------------------------------------------------------

  defmodule MockPassed do
    def run(_opts),
      do: {:ok, %DrValidator.AppResult{name: "mock", status: :passed}}
  end

  defmodule MockFailed do
    def run(_opts),
      do: {:error, %DrValidator.AppResult{name: "mock", status: :failed, error_message: "fail"}}
  end

  defmodule MockPartial do
    def run(_opts),
      do: {:error, %DrValidator.AppResult{name: "mock", status: :partial}}
  end

  # ---------------------------------------------------------------------------
  # Unit: parse_args/1
  # ---------------------------------------------------------------------------

  describe "parse_args/1" do
    test "parses --perimeter flag" do
      assert {:ok, opts} = CLI.parse_args(["--perimeter", "pi-full"])
      assert opts.perimeter == "pi-full"
    end

    test "parses --report-path flag" do
      assert {:ok, opts} =
               CLI.parse_args(["--perimeter", "pi-full", "--report-path", "/tmp/r.json"])

      assert opts.report_path == "/tmp/r.json"
    end

    test "parses --app-timeout-ms as integer" do
      assert {:ok, opts} =
               CLI.parse_args(["--perimeter", "pi-full", "--app-timeout-ms", "30000"])

      assert opts.app_timeout_ms == 30_000
    end

    test "parses --perimeters-path flag" do
      assert {:ok, opts} =
               CLI.parse_args(["--perimeter", "pi-full", "--perimeters-path", "/etc/test.json"])

      assert opts.perimeters_path == "/etc/test.json"
    end

    test "missing --perimeter returns :usage_error" do
      assert {:error, :usage_error} = CLI.parse_args([])
    end

    test "missing --perimeter returns :usage_error even with other flags" do
      assert {:error, :usage_error} = CLI.parse_args(["--report-path", "/tmp/r.json"])
    end

    test "--help returns :help" do
      assert :help = CLI.parse_args(["--help"])
    end
  end

  # ---------------------------------------------------------------------------
  # PBT: parse_args properties
  # ---------------------------------------------------------------------------

  property "any non-empty perimeter id parses without usage_error" do
    check all id <- string(:alphanumeric, min_length: 1) do
      result = CLI.parse_args(["--perimeter", id])
      # alphanumeric ids always succeed (no special chars that confuse OptionParser)
      assert {:ok, opts} = result
      assert opts.perimeter == id
    end
  end

  property "missing --perimeter always yields usage_error" do
    # Generate flag/value pairs that do NOT include --perimeter
    safe_flags = [
      ["--report-path", "/tmp/r.json"],
      ["--app-timeout-ms", "1000"],
      ["--perimeters-path", "/etc/p.json"],
      []
    ]

    check all extra <- member_of(safe_flags) do
      result = CLI.parse_args(extra)
      assert result == {:error, :usage_error}
    end
  end

  property "--app-timeout-ms is always parsed as integer when valid" do
    check all ms <- positive_integer() do
      args = ["--perimeter", "pi-full", "--app-timeout-ms", Integer.to_string(ms)]
      assert {:ok, opts} = CLI.parse_args(args)
      assert opts.app_timeout_ms == ms
    end
  end

  # ---------------------------------------------------------------------------
  # Unit: exit_code_for/1
  # ---------------------------------------------------------------------------

  describe "exit_code_for/1" do
    test ":passed -> 0" do
      assert CLI.exit_code_for(:passed) == 0
    end

    test ":failed -> 1" do
      assert CLI.exit_code_for(:failed) == 1
    end

    test ":partial -> 2" do
      assert CLI.exit_code_for(:partial) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # PBT: dispatch — aggregate exit codes via Runner
  # ---------------------------------------------------------------------------

  property "all :passed validators -> overall :passed -> exit code 0" do
    check all app_names <- list_of(string(:alphanumeric, min_length: 1), min_length: 1) do
      validators = Map.new(app_names, &{&1, MockPassed})

      perimeter = %DrValidator.Perimeter{
        id: "test",
        host: "test-host",
        apps: app_names,
        canary: false
      }

      report = DrValidator.Runner.run(perimeter, validators: validators)
      assert report.overall_status == :passed
      assert CLI.exit_code_for(report.overall_status) == 0
    end
  end

  property "at least one :failed (no :partial) -> overall :failed -> exit code 1" do
    check all passing <- list_of(string(:alphanumeric, min_length: 2), min_length: 0),
              failing <- list_of(string(:alphanumeric, min_length: 2), min_length: 1) do
      passing_names = Enum.map(passing, &("p_" <> &1))
      failing_names = Enum.map(failing, &("f_" <> &1))
      all_names = passing_names ++ failing_names

      validators =
        Map.merge(
          Map.new(passing_names, &{&1, MockPassed}),
          Map.new(failing_names, &{&1, MockFailed})
        )

      perimeter = %DrValidator.Perimeter{
        id: "test",
        host: "test-host",
        apps: all_names,
        canary: false
      }

      report = DrValidator.Runner.run(perimeter, validators: validators)
      assert report.overall_status == :failed
      assert CLI.exit_code_for(report.overall_status) == 1
    end
  end

  property "at least one :partial -> overall :partial -> exit code 2" do
    check all partial <- list_of(string(:alphanumeric, min_length: 2), min_length: 1),
              others <- list_of(string(:alphanumeric, min_length: 2)) do
      partial_names = Enum.map(partial, &("partial_" <> &1))
      other_names = Enum.map(others, &("other_" <> &1))
      all_names = partial_names ++ other_names

      validators =
        Map.merge(
          Map.new(partial_names, &{&1, MockPartial}),
          Map.new(other_names, &{&1, MockPassed})
        )

      perimeter = %DrValidator.Perimeter{
        id: "test",
        host: "test-host",
        apps: all_names,
        canary: false
      }

      report = DrValidator.Runner.run(perimeter, validators: validators)
      assert report.overall_status == :partial
      assert CLI.exit_code_for(report.overall_status) == 2
    end
  end
end
