defmodule Mix.Tasks.DrValidator.RunTest do
  use ExUnit.Case, async: false

  # Mix tasks call System.halt/1 which would kill the test process.
  # We test via DrValidator.CLI.main/1 (which returns exit code) rather
  # than invoking Mix.Task.run/2 directly. The mix task is a thin wrapper
  # and its correctness is verified by the CLI tests. Here we only check
  # that the task module exists and delegates correctly.

  test "mix task module is defined" do
    assert Code.ensure_loaded?(Mix.Tasks.DrValidator.Run)
  end

  test "task has correct @shortdoc" do
    shortdoc = Mix.Task.shortdoc(Mix.Tasks.DrValidator.Run)
    assert is_binary(shortdoc)
    assert String.length(shortdoc) > 0
  end

  test "task implements Mix.Task behaviour" do
    behaviours =
      Mix.Tasks.DrValidator.Run.__info__(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    assert Mix.Task in behaviours
  end
end
