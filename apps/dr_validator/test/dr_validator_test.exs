defmodule DrValidatorTest do
  use ExUnit.Case
  doctest DrValidator

  test "greets the world" do
    assert DrValidator.hello() == :world
  end
end
