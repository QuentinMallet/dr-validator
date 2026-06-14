defmodule DrValidator.AppResult do
  @moduledoc """
  Result of running a single app validator.
  """

  @derive Jason.Encoder
  @enforce_keys [:name, :status]
  defstruct [
    :name,
    :status,
    :duration_ms,
    :started_at,
    :completed_at,
    :error_message,
    details: %{}
  ]

  @type status :: :passed | :failed | :partial
  @type t :: %__MODULE__{
          name: String.t(),
          status: status(),
          duration_ms: non_neg_integer() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          error_message: String.t() | nil,
          details: map()
        }
end
