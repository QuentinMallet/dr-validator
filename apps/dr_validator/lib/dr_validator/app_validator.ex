defmodule DrValidator.AppValidator do
  @moduledoc """
  Behaviour for DR app validators. Each app under test implements this.
  """

  alias DrValidator.AppResult

  @doc "Human-readable name identifying this validator."
  @callback name() :: String.t()

  @doc """
  Run the validation for this app.

  Returns `{:ok, result}` on pass or partial, `{:error, result}` on failure.
  """
  @callback run(opts :: map()) :: {:ok, AppResult.t()} | {:error, AppResult.t()}

  @doc """
  Describe the expected data shape for this app, or nil if not applicable.
  """
  @callback expected_data() :: map() | nil
end
