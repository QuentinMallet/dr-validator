defmodule DrValidator.Apps do
  @moduledoc """
  Registry mapping app names to their validator modules.

  Each entry maps an app name (as it appears in the perimeter JSON) to the
  module that implements `AppValidator` behaviour for that app.

  ## Stub state

  The registry is currently empty. The openbao validator
  (`DrValidator.Apps.Openbao.RestoreTest`) is implemented in the
  `dr_validator_openbao` umbrella app and will be registered there via the
  `:validator_lookup` injection point in the CLI. Registry entries are added
  as each app validator is implemented.

  ## Usage

  Pass `validator_lookup: &DrValidator.Apps.lookup/1` in Runner opts, or
  use `DrValidator.CLI` which wires this automatically.
  """

  @registry %{}

  @doc """
  Look up the validator module for `app_name`.

  Returns the module if registered, `nil` otherwise.
  Runner treats `nil` as "no validator registered" and emits a `:failed`
  AppResult for that app.
  """
  @spec lookup(String.t()) :: module() | nil
  def lookup(app_name), do: Map.get(@registry, app_name)
end
