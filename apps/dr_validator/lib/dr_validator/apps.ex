defmodule DrValidator.Apps do
  @moduledoc """
  Registry mapping app names to their `AppValidator` implementation modules.

  ## Runtime configuration

  Validators are registered in application environment rather than as a
  compile-time module attribute. This eliminates the cross-sub-app compile
  dependency: the core `dr_validator` sub-app no longer needs a transitive
  compile reference to `DrValidator.Apps.Openbao.RestoreTest` (which lives in
  the sibling `dr_validator_openbao` sub-app).

  Register validators in the umbrella's shared `config/config.exs`:

      config :dr_validator, validators: %{
        "openbao" => DrValidator.Apps.Openbao.RestoreTest
      }

  ## Unloaded modules

  `lookup/1` guards with `Code.ensure_loaded?/1` so that a validator name
  configured in the map but whose module is not actually loaded (e.g. when
  running only the core sub-app in isolation) returns `nil` rather than an
  atom that would crash at `module.run/1` call sites.

  ## Trade-offs

  | Approach        | Compile dep | Catches typos  | Absent sub-app |
  |-----------------|-------------|----------------|----------------|
  | Compile-time `@registry` | Yes (wrong) | At compile time | Compile error |
  | Runtime config (this)   | No          | At runtime      | nil (safe)    |
  """

  @doc """
  Look up a validator module by app name.

  Returns the module atom if configured and loadable, `nil` otherwise.
  """
  @spec lookup(String.t()) :: module() | nil
  def lookup(name) do
    case Application.get_env(:dr_validator, :validators, %{}) |> Map.get(name) do
      nil -> nil
      mod -> if Code.ensure_loaded?(mod), do: mod, else: nil
    end
  end

  @doc "Return all registered validators as a `name => module` map."
  @spec all() :: %{String.t() => module()}
  def all, do: Application.get_env(:dr_validator, :validators, %{})
end
