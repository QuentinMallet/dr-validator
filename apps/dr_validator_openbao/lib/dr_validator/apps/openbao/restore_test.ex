defmodule DrValidator.Apps.Openbao.RestoreTest do
  @moduledoc """
  AppValidator for OpenBao DR validation.

  Checks (in order):
  1. `/v1/sys/health` — OpenBao is initialized and unsealed.
  2. `/v1/sys/mounts` — the `kv/` secrets engine is mounted.
  3. `/v1/kv/data/canary` — the canary secret has value `"ok"`.

  Options accepted by `run/1`:
  - `:base_url` — OpenBao base URL (default: `"http://127.0.0.1:8200"`)
  - `:token` — Vault token used for authenticated requests (default: `"root"`)
  """

  @behaviour DrValidator.AppValidator

  alias DrValidator.AppResult

  @impl DrValidator.AppValidator
  def name, do: "openbao"

  @impl DrValidator.AppValidator
  def expected_data do
    %{mount: "kv/", canary_path: "kv/data/canary", canary_value: "ok"}
  end

  @impl DrValidator.AppValidator
  def run(opts) do
    base_url = Map.get(opts, :base_url, "http://127.0.0.1:8200")
    token = Map.get(opts, :token, "root")
    t0 = System.monotonic_time(:millisecond)

    with :ok <- check_health(base_url),
         :ok <- check_mounts(base_url, token),
         :ok <- check_canary(base_url, token) do
      {:ok, %AppResult{name: name(), status: :passed, duration_ms: elapsed(t0)}}
    else
      {:error, msg} ->
        {:error, %AppResult{name: name(), status: :failed, duration_ms: elapsed(t0), error_message: msg}}
    end
  end

  # ------------------------------------------------------------------
  # Private
  # ------------------------------------------------------------------

  defp elapsed(t0), do: System.monotonic_time(:millisecond) - t0

  defp check_health(base_url) do
    case HTTPoison.get(base_url <> "/v1/sys/health") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_health(body)

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"initialized" => false}} -> {:error, "openbao not initialized (status #{code})"}
          {:ok, %{"sealed" => true}} -> {:error, "openbao is sealed (status #{code})"}
          _ -> {:error, "unexpected health status #{code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "connection error reaching openbao health endpoint: #{inspect(reason)}"}
    end
  end

  defp parse_health(body) do
    case Jason.decode(body) do
      {:ok, %{"initialized" => true, "sealed" => false}} -> :ok
      {:ok, %{"initialized" => false}} -> {:error, "openbao not initialized"}
      {:ok, %{"sealed" => true}} -> {:error, "openbao is sealed"}
      {:ok, _} -> {:error, "unexpected health response body"}
      {:error, _} -> {:error, "could not parse health response"}
    end
  end

  defp check_mounts(base_url, token) do
    case HTTPoison.get(base_url <> "/v1/sys/mounts", [{"X-Vault-Token", token}]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, mounts} when is_map(mounts) ->
            if Map.has_key?(mounts, "kv/") do
              :ok
            else
              {:error, "required kv/ mount not found; present: #{inspect(Map.keys(mounts))}"}
            end

          _ ->
            {:error, "could not parse mounts response"}
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "unexpected status #{code} from /v1/sys/mounts"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "connection error reaching openbao mounts endpoint: #{inspect(reason)}"}
    end
  end

  defp check_canary(base_url, token) do
    case HTTPoison.get(base_url <> "/v1/kv/data/canary", [{"X-Vault-Token", token}]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"data" => %{"data" => %{"value" => "ok"}}}} ->
            :ok

          {:ok, %{"data" => %{"data" => %{"value" => val}}}} ->
            {:error, "canary value mismatch: expected \"ok\", got #{inspect(val)}"}

          _ ->
            {:error, "unexpected canary response format"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "canary secret not found at kv/data/canary"}

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "unexpected status #{code} from /v1/kv/data/canary"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "connection error reaching openbao canary endpoint: #{inspect(reason)}"}
    end
  end
end
