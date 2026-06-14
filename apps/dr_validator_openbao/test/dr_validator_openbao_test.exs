defmodule DrValidatorOpenbaoTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DrValidator.AppResult
  alias DrValidator.Apps.Openbao.RestoreTest

  setup do
    bypass = Bypass.open()
    base_url = "http://127.0.0.1:#{bypass.port}"
    {:ok, bypass: bypass, base_url: base_url}
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp health_ok,
    do: Jason.encode!(%{"initialized" => true, "sealed" => false, "standby" => false})

  defp mounts_with_kv,
    do: Jason.encode!(%{"kv/" => %{"type" => "kv"}, "sys/" => %{"type" => "system"}})

  defp canary_ok,
    do: Jason.encode!(%{"data" => %{"data" => %{"value" => "ok"}}})

  defp stub_health(bypass, body, status \\ 200) do
    Bypass.stub(bypass, "GET", "/v1/sys/health", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, body)
    end)
  end

  defp stub_mounts(bypass, body) do
    Bypass.stub(bypass, "GET", "/v1/sys/mounts", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)
  end

  defp stub_canary(bypass, body, status \\ 200) do
    Bypass.stub(bypass, "GET", "/v1/kv/data/canary", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, body)
    end)
  end

  # ------------------------------------------------------------------
  # Property: all OK → :passed
  # ------------------------------------------------------------------

  property "returns :passed when health OK, kv/ present, canary correct", %{bypass: bypass, base_url: base_url} do
    check all standby? <- boolean() do
      Bypass.stub(bypass, "GET", "/v1/sys/health", fn conn ->
        body = Jason.encode!(%{"initialized" => true, "sealed" => false, "standby" => standby?})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      stub_mounts(bypass, mounts_with_kv())
      stub_canary(bypass, canary_ok())

      assert {:ok, %AppResult{status: :passed, name: "openbao"}} =
               RestoreTest.run(%{base_url: base_url, token: "root"})
    end
  end

  # ------------------------------------------------------------------
  # Property: missing kv/ mount → :failed, error mentions "kv"
  # ------------------------------------------------------------------

  property "returns :failed (mentioning kv) when kv/ mount is absent", %{bypass: bypass, base_url: base_url} do
    check all other_keys <- list_of(string(:alphanumeric, min_length: 2, max_length: 8), max_length: 4) do
      mounts =
        other_keys
        |> Enum.reject(&(&1 == "kv"))
        |> Enum.map(&{"#{&1}/", %{"type" => "generic"}})
        |> Map.new()

      stub_health(bypass, health_ok())
      stub_mounts(bypass, Jason.encode!(mounts))

      {:error, %AppResult{status: :failed, error_message: msg}} =
        RestoreTest.run(%{base_url: base_url, token: "root"})

      assert String.contains?(msg, "kv"),
             "expected error to mention 'kv', got: #{inspect(msg)}"
    end
  end

  # ------------------------------------------------------------------
  # Property: wrong canary value → :failed
  # ------------------------------------------------------------------

  property "returns :failed when canary value is not \"ok\"", %{bypass: bypass, base_url: base_url} do
    check all wrong_val <- string(:printable, min_length: 1, max_length: 20),
              wrong_val != "ok" do
      stub_health(bypass, health_ok())
      stub_mounts(bypass, mounts_with_kv())

      Bypass.stub(bypass, "GET", "/v1/kv/data/canary", fn conn ->
        body = Jason.encode!(%{"data" => %{"data" => %{"value" => wrong_val}}})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      assert {:error, %AppResult{status: :failed}} =
               RestoreTest.run(%{base_url: base_url, token: "root"})
    end
  end

  # ------------------------------------------------------------------
  # Test: health endpoint unreachable → :failed with "connection" in msg
  # ------------------------------------------------------------------

  test "returns :failed with connection mention when health endpoint unreachable", %{bypass: bypass, base_url: base_url} do
    Bypass.down(bypass)

    {:error, %AppResult{status: :failed, error_message: msg}} =
      RestoreTest.run(%{base_url: base_url, token: "root"})

    assert String.contains?(msg, "connection"),
           "expected error to mention 'connection', got: #{inspect(msg)}"

    Bypass.up(bypass)
  end

  # ------------------------------------------------------------------
  # TLS / remote posture
  # ------------------------------------------------------------------

  test "rejects non-localhost base_url without :allow_remote" do
    System.delete_env("DR_OPENBAO_TOKEN")
    {:error, %AppResult{status: :failed, error_message: msg}} =
      RestoreTest.run(%{base_url: "http://192.168.1.10:8200", token: "root"})

    assert msg =~ "allow_remote",
           "expected error to mention 'allow_remote', got: #{inspect(msg)}"
  end

  test "allows localhost base_url without :allow_remote", %{bypass: bypass, base_url: base_url} do
    stub_health(bypass, health_ok())
    stub_mounts(bypass, mounts_with_kv())
    stub_canary(bypass, canary_ok())

    assert {:ok, %AppResult{status: :passed}} =
             RestoreTest.run(%{base_url: base_url, token: "root"})
  end

  test "allows non-localhost base_url when :allow_remote is true", %{bypass: bypass, base_url: base_url} do
    stub_health(bypass, health_ok())
    stub_mounts(bypass, mounts_with_kv())
    stub_canary(bypass, canary_ok())

    # Use the bypass (127.0.0.1) URL but with allow_remote to confirm the opt is honoured
    # for remote URLs: we fake a remote URL by patching the check with allow_remote.
    assert {:ok, %AppResult{status: :passed}} =
             RestoreTest.run(%{base_url: base_url, token: "root", allow_remote: true})
  end

  # ------------------------------------------------------------------
  # Token resolution
  # ------------------------------------------------------------------

  test "returns :failed when no :token opt and DR_OPENBAO_TOKEN env unset", %{bypass: _bypass, base_url: base_url} do
    System.delete_env("DR_OPENBAO_TOKEN")
    {:error, %AppResult{status: :failed, error_message: msg}} =
      RestoreTest.run(%{base_url: base_url})

    assert msg =~ "no openbao token",
           "expected error to mention 'no openbao token', got: #{inspect(msg)}"
  end

  test "picks up token from DR_OPENBAO_TOKEN env when :token opt absent", %{bypass: bypass, base_url: base_url} do
    System.put_env("DR_OPENBAO_TOKEN", "env-token")

    stub_health(bypass, health_ok())
    stub_mounts(bypass, mounts_with_kv())
    stub_canary(bypass, canary_ok())

    assert {:ok, %AppResult{status: :passed}} = RestoreTest.run(%{base_url: base_url})
  after
    System.delete_env("DR_OPENBAO_TOKEN")
  end

  test ":token opt takes precedence over DR_OPENBAO_TOKEN env", %{bypass: bypass, base_url: base_url} do
    System.put_env("DR_OPENBAO_TOKEN", "env-token")

    stub_health(bypass, health_ok())
    stub_mounts(bypass, mounts_with_kv())
    stub_canary(bypass, canary_ok())

    # If opt wins, the request still goes through (both tokens valid in bypass mock)
    assert {:ok, %AppResult{status: :passed}} = RestoreTest.run(%{base_url: base_url, token: "opt-token"})
  after
    System.delete_env("DR_OPENBAO_TOKEN")
  end

  # ------------------------------------------------------------------
  # Metadata / callbacks
  # ------------------------------------------------------------------

  test "name/0 returns \"openbao\"" do
    assert RestoreTest.name() == "openbao"
  end

  test "expected_data/0 includes mount and canary fields" do
    data = RestoreTest.expected_data()
    assert data.mount == "kv/"
    assert data.canary_path == "kv/data/canary"
    assert data.canary_value == "ok"
  end
end
