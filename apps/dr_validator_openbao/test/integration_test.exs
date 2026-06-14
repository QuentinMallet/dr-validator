defmodule DrValidatorOpenbao.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias DrValidator.{AppResult, Perimeter, Runner}
  alias DrValidator.Apps.Openbao.RestoreTest

  # Use 18200 to avoid collision with any bao dev instance already on 8200
  @base_url "http://127.0.0.1:18200"
  @token "root"
  @kv_mount "kv"

  # ------------------------------------------------------------------
  # Setup: spawn bao -dev, mount kv/, write canary
  # ------------------------------------------------------------------

  setup_all do
    bao_path = System.find_executable("bao") || raise "bao not found in PATH (run inside nix develop)"

    bao_port =
      Port.open(
        {:spawn_executable, bao_path},
        [
          :binary,
          :exit_status,
          {:args,
           [
             "server",
             "-dev",
             "-dev-root-token-id=#{@token}",
             "-dev-listen-address=127.0.0.1:18200"
           ]}
        ]
      )

    # Poll until bao health endpoint responds (up to 10 s)
    :ok = await_bao(@base_url, 100)

    # Mount kv/ as KV v2 (dev mode only mounts secret/ by default)
    {:ok, _} =
      HTTPoison.post(
        "#{@base_url}/v1/sys/mounts/#{@kv_mount}",
        Jason.encode!(%{type: "kv", options: %{version: "2"}}),
        auth_headers()
      )

    # Brief settle time for mount activation
    Process.sleep(300)

    # Write canary secret
    {:ok, _} =
      HTTPoison.post(
        "#{@base_url}/v1/#{@kv_mount}/data/canary",
        Jason.encode!(%{data: %{value: "ok"}}),
        auth_headers()
      )

    # Teardown: close the port then await the OS process exit.
    # Port.close/1 sends EOF to the process but does not guarantee it has exited;
    # we wait for the {:exit_status, _} message so the port's OS PID is reaped
    # before the next test suite run. pkill is a fallback if the graceful close
    # does not deliver exit_status within 2 s.
    on_exit(fn ->
      try do
        Port.close(bao_port)
      rescue
        ArgumentError -> :already_closed
      end

      receive do
        {^bao_port, {:exit_status, _}} -> :ok
      after
        2000 ->
          System.cmd("pkill", ["-f", "bao server -dev -dev-listen-address=127.0.0.1:18200"],
            stderr_to_stdout: true
          )
      end
    end)

    :ok
  end

  # ------------------------------------------------------------------
  # Integration test
  # ------------------------------------------------------------------

  test "openbao validator passes end-to-end against bao -dev" do
    perimeter = %Perimeter{id: "integration-test", host: "localhost", apps: ["openbao"], canary: true}

    report =
      Runner.run(perimeter,
        validator_lookup: fn
          "openbao" -> RestoreTest
          _ -> nil
        end,
        base_url: @base_url,
        token: @token
      )

    assert report.overall_status == :passed,
           "expected :passed, got #{inspect(report.overall_status)}; " <>
             "app results: #{inspect(report.apps)}"

    assert [%AppResult{name: "openbao", status: :passed, duration_ms: dur}] = report.apps
    assert is_integer(dur) and dur >= 0
  end

  # ------------------------------------------------------------------
  # Private
  # ------------------------------------------------------------------

  defp auth_headers do
    [{"X-Vault-Token", @token}, {"Content-Type", "application/json"}]
  end

  # Poll /v1/sys/health until it returns 200 or we exhaust retries.
  defp await_bao(_base_url, 0), do: {:error, :timeout}

  defp await_bao(base_url, retries_left) do
    case HTTPoison.get(base_url <> "/v1/sys/health", [], recv_timeout: 500) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      _ ->
        Process.sleep(100)
        await_bao(base_url, retries_left - 1)
    end
  end
end
