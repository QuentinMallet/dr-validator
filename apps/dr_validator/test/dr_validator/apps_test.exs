defmodule DrValidator.AppsTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias DrValidator.Apps

  setup do
    original = Application.get_env(:dr_validator, :validators)

    on_exit(fn ->
      if original do
        Application.put_env(:dr_validator, :validators, original)
      else
        Application.delete_env(:dr_validator, :validators)
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Fix 2 — runtime config-driven validator registry
  # ---------------------------------------------------------------------------

  describe "lookup/1" do
    test "returns configured module when loadable" do
      Application.put_env(:dr_validator, :validators, %{"myapp" => String})
      assert Apps.lookup("myapp") == String
    end

    test "returns nil for unregistered name" do
      Application.put_env(:dr_validator, :validators, %{"myapp" => String})
      assert Apps.lookup("other") == nil
    end

    test "returns nil when module configured but not loadable" do
      # This atom will never correspond to a loaded module
      Application.put_env(:dr_validator, :validators, %{
        "ghost" => :"Elixir.DrValidator.Test.NeverExistsModule"
      })

      refute Code.ensure_loaded?(:"Elixir.DrValidator.Test.NeverExistsModule")
      assert Apps.lookup("ghost") == nil
    end

    test "returns nil with empty registry" do
      Application.put_env(:dr_validator, :validators, %{})
      assert Apps.lookup("anything") == nil
    end

    test "returns nil with no config key" do
      Application.delete_env(:dr_validator, :validators)
      assert Apps.lookup("openbao") == nil
    end

    property "returns correct module for each registered name; nil for unregistered" do
      # Use well-known stdlib modules as stand-in validator modules (always loadable)
      loadable = [String, Integer, Atom, List, Map, Keyword, Enum, Float]

      check all pairs <-
                  StreamData.list_of(
                    StreamData.tuple(
                      {StreamData.string(:alphanumeric, min_length: 1), StreamData.member_of(loadable)}
                    ),
                    min_length: 1,
                    max_length: 6
                  ) do
        registry = Map.new(pairs)
        Application.put_env(:dr_validator, :validators, registry)

        Enum.each(registry, fn {name, mod} ->
          assert Apps.lookup(name) == mod,
                 "expected #{inspect(mod)} for #{inspect(name)}, got #{inspect(Apps.lookup(name))}"
        end)

        assert Apps.lookup("__z_definitely_not_registered__") == nil
      end
    end
  end

  describe "all/0" do
    test "returns the full registry map" do
      reg = %{"openbao" => String, "zitadel" => Integer}
      Application.put_env(:dr_validator, :validators, reg)
      assert Apps.all() == reg
    end

    test "returns empty map with no config" do
      Application.delete_env(:dr_validator, :validators)
      assert Apps.all() == %{}
    end
  end
end
