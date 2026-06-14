defmodule DrValidator.Report do
  @moduledoc """
  Versioned DR validation report aggregating per-app results.

  overall_status derivation:
    :passed  — all apps :passed
    :partial — any app :partial (regardless of :failed count)
    :failed  — any app :failed, none :partial
  """

  @derive Jason.Encoder
  @enforce_keys [:perimeter_id, :apps]
  defstruct [
    :perimeter_id,
    :started_at,
    :completed_at,
    :overall_status,
    apps: [],
    schema_version: 1
  ]

  @type overall_status :: :passed | :failed | :partial
  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          perimeter_id: String.t(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          overall_status: overall_status(),
          apps: [DrValidator.AppResult.t()]
        }

  @doc """
  Build a Report from keyword options, deriving overall_status from apps list.

  Required keys: `:perimeter_id`, `:apps`
  Optional keys: `:started_at`, `:completed_at`
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    apps = Keyword.fetch!(opts, :apps)

    %__MODULE__{
      schema_version: 1,
      perimeter_id: Keyword.fetch!(opts, :perimeter_id),
      started_at: Keyword.get(opts, :started_at),
      completed_at: Keyword.get(opts, :completed_at),
      overall_status: derive_status(apps),
      apps: apps
    }
  end

  @spec derive_status([DrValidator.AppResult.t()]) :: overall_status()
  defp derive_status(apps) do
    statuses = Enum.map(apps, & &1.status)

    cond do
      :partial in statuses -> :partial
      :failed in statuses -> :failed
      true -> :passed
    end
  end
end
