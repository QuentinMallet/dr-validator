defmodule DrValidator.Apps do
  @moduledoc """
  Registry mapping app names to their AppValidator implementation modules.

  Validator modules live in separate umbrella sub-apps (e.g. `dr_validator_openbao`).
  Referencing them here as atoms avoids a compile-time circular dependency while
  still enabling callers to resolve validators by name at runtime.
  """

  @registry %{
    "openbao" => DrValidator.Apps.Openbao.RestoreTest
  }

  @doc "Look up a validator module by app name. Returns `nil` if not registered."
  @spec lookup(String.t()) :: module() | nil
  def lookup(name), do: Map.get(@registry, name)

  @doc "Return all registered validators as a `name => module` map."
  @spec all() :: %{String.t() => module()}
  def all, do: @registry
end
