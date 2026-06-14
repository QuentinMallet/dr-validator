defmodule DrValidator.ReportWriter do
  @moduledoc """
  Writes a `DrValidator.Report` to disk as pretty-printed JSON using an
  atomic rename so readers never see a partial file.

  Write sequence:
    1. Ensure parent directory exists (`File.mkdir_p!`).
    2. Sort apps by name for deterministic output.
    3. Encode to JSON with `Jason.encode!(pretty: true)`.
    4. Write to `<path>.tmp.<16-char random hex>`.
    5. `chmod 0o640` on the tmp file.
    6. `File.rename!/2` — atomic on POSIX same-filesystem.
  """

  alias DrValidator.Report

  @default_path "/var/log/dr-validator/report.json"

  @doc """
  Write `report` to `path` atomically.

  Returns `:ok` on success or `{:error, reason}` on failure.
  The parent directory is created if it does not exist.
  """
  @spec write(Report.t(), Path.t()) :: :ok | {:error, term()}
  def write(%Report{} = report, path \\ @default_path) do
    with :ok <- ensure_dir(path),
         {:ok, tmp} <- write_tmp(report, path),
         :ok <- File.chmod(tmp, 0o640),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, _} = err ->
        err
    end
  end

  # --- Private helpers ---

  defp ensure_dir(path) do
    path |> Path.dirname() |> File.mkdir_p()
  end

  defp write_tmp(report, path) do
    rand_suffix = :crypto.strong_rand_bytes(8) |> Base.encode16()
    tmp = "#{path}.tmp.#{rand_suffix}"
    sorted_report = sort_apps(report)

    case Jason.encode(sorted_report, pretty: true) do
      {:ok, json} ->
        case File.write(tmp, json) do
          :ok -> {:ok, tmp}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  defp sort_apps(%Report{apps: apps} = report) do
    %{report | apps: Enum.sort_by(apps, & &1.name)}
  end
end
