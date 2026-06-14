defmodule DrValidator.RunnerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DrValidator.{AppResult, Perimeter, Report, Runner}

  # ---------------------------------------------------------------------------
  # Fake validator modules
  # ---------------------------------------------------------------------------

  defmodule FakePassedValidator do
    @behaviour DrValidator.AppValidator
    def name, do: "fake-passed"
    def run(_opts), do: {:ok, %AppResult{name: "fake-passed", status: :passed}}
    def expected_data, do: nil
  end

  defmodule FakeFailedValidator do
    @behaviour DrValidator.AppValidator
    def name, do: "fake-failed"

    def run(_opts),
      do: {:error, %AppResult{name: "fake-failed", status: :failed, error_message: "intentional failure"}}

    def expected_data, do: nil
  end

  defmodule FakePartialValidator do
    @behaviour DrValidator.AppValidator
    def name, do: "fake-partial"
    def run(_opts), do: {:ok, %AppResult{name: "fake-partial", status: :partial}}
    def expected_data, do: nil
  end

  # Sleeps far beyond any test-level timeout to simulate a hung validator.
  defmodule FakeTimeoutValidator do
    @behaviour DrValidator.AppValidator
    def name, do: "fake-timeout"

    def run(_opts) do
      Process.sleep(10_000)
      {:ok, %AppResult{name: "fake-timeout", status: :passed}}
    end

    def expected_data, do: nil
  end

  # Raises an exception to simulate a crashing validator.
  defmodule FakeCrashValidator do
    @behaviour DrValidator.AppValidator
    def name, do: "fake-crash"
    def run(_opts), do: raise("boom from FakeCrashValidator")
    def expected_data, do: nil
  end

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  defp app_name_gen, do: StreamData.string(:alphanumeric, min_length: 1)

  defp healthy_validator_gen,
    do: StreamData.member_of([FakePassedValidator, FakeFailedValidator, FakePartialValidator])

  defp perimeter_gen do
    gen all id <- StreamData.string(:alphanumeric, min_length: 1),
            apps <- StreamData.list_of(app_name_gen(), min_length: 1, max_length: 5) do
      # Deduplicate to keep the "exactly once" property tractable.
      %Perimeter{id: id, host: "test-host", apps: Enum.uniq(apps), canary: true}
    end
  end

  # A validator_lookup function that maps every name to the same module.
  defp uniform_lookup(mod), do: fn _name -> mod end

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  property "every app in perimeter.apps appears exactly once in report.apps" do
    check all perimeter <- perimeter_gen(),
              validator <- healthy_validator_gen() do
      report = Runner.run(perimeter, validator_lookup: uniform_lookup(validator))

      result_names = Enum.map(report.apps, & &1.name)
      assert length(result_names) == length(perimeter.apps)
      assert Enum.sort(result_names) == Enum.sort(perimeter.apps)
    end
  end

  property "AppResult ordering matches perimeter.apps order (sequential semantics)" do
    check all perimeter <- perimeter_gen(),
              validator <- healthy_validator_gen() do
      report = Runner.run(perimeter, validator_lookup: uniform_lookup(validator))
      assert Enum.map(report.apps, & &1.name) == perimeter.apps
    end
  end

  property "report.perimeter_id matches input perimeter.id" do
    check all perimeter <- perimeter_gen(),
              validator <- healthy_validator_gen() do
      report = Runner.run(perimeter, validator_lookup: uniform_lookup(validator))
      assert report.perimeter_id == perimeter.id
    end
  end

  property "timeout: validator sleeping beyond :app_timeout_ms yields :failed AppResult with 'timeout'" do
    check all perimeter <- perimeter_gen() do
      report =
        Runner.run(perimeter,
          validator_lookup: uniform_lookup(FakeTimeoutValidator),
          # 50 ms — validator sleeps 10 s
          app_timeout_ms: 50
        )

      for result <- report.apps do
        assert result.status == :failed
        assert result.error_message =~ "timeout"
      end
    end
  end

  property "crash: validator that raises yields :failed AppResult whose error_message contains the exception" do
    check all perimeter <- perimeter_gen() do
      report = Runner.run(perimeter, validator_lookup: uniform_lookup(FakeCrashValidator))

      for result <- report.apps do
        assert result.status == :failed
        assert result.error_message =~ "boom"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests
  # ---------------------------------------------------------------------------

  test "uses :validators map when :validator_lookup is not provided" do
    perimeter = %Perimeter{id: "p1", host: "test-host", apps: ["openbao"], canary: true}
    report = Runner.run(perimeter, validators: %{"openbao" => FakePassedValidator})
    assert length(report.apps) == 1
    assert hd(report.apps).status == :passed
  end

  test "missing validator entry yields :failed AppResult mentioning the app name" do
    perimeter = %Perimeter{id: "p1", host: "test-host", apps: ["unknown_app"], canary: true}
    report = Runner.run(perimeter, validators: %{})
    assert hd(report.apps).status == :failed
    assert hd(report.apps).error_message =~ "unknown_app"
  end

  test "report_writer fn is called with the finished report" do
    perimeter = %Perimeter{id: "p1", host: "test-host", apps: ["app1"], canary: true}
    test_pid = self()
    writer = fn report -> send(test_pid, {:written, report}); report end

    Runner.run(perimeter,
      validator_lookup: uniform_lookup(FakePassedValidator),
      report_writer: writer
    )

    assert_received {:written, %Report{}}
  end

  test "each AppResult carries a non-nil duration_ms" do
    perimeter = %Perimeter{id: "p1", host: "test-host", apps: ["a", "b"], canary: true}
    report = Runner.run(perimeter, validator_lookup: uniform_lookup(FakePassedValidator))
    for result <- report.apps, do: assert(is_integer(result.duration_ms))
  end
end
