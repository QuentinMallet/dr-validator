defmodule DrValidator.PerimeterLoader do
  @moduledoc """
  Loads DR validation perimeters from a JSON file.

  The file path is resolved in this priority order:
    1. Explicit `path` argument (when calling the 2-arity variants)
    2. `DR_PERIMETERS_PATH` environment variable
    3. Default `/etc/dr-perimeters.json`

  Expected JSON shape (array of objects):

      [
        {
          "id": "pi-full",
          "host": "pi",
          "apps": ["openbao", "zitadel"],
          "canary": true,
          "archiveAgeDaysMax": 30
        }
      ]

  `archiveAgeDaysMax` is optional.
  """

  alias DrValidator.Perimeter

  @default_path "/etc/dr-perimeters.json"

  @type load_error :: :file_not_found | :malformed
  @type get_error  :: :file_not_found | :malformed | :not_found

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "List all perimeters from the default path."
  @spec list() :: {:ok, [Perimeter.t()]} | {:error, load_error()}
  def list, do: list(resolve_path())

  @doc "List all perimeters from `path`."
  @spec list(String.t()) :: {:ok, [Perimeter.t()]} | {:error, load_error()}
  def list(path) do
    with {:ok, raw} <- read_file(path),
         {:ok, decoded} <- parse_json(raw),
         {:ok, perimeters} <- validate_and_cast(decoded) do
      {:ok, perimeters}
    end
  end

  @doc "Get a single perimeter by `id` from the default path."
  @spec get(String.t()) :: {:ok, Perimeter.t()} | {:error, get_error()}
  def get(perimeter_id), do: get(resolve_path(), perimeter_id)

  @doc "Get a single perimeter by `id` from `path`."
  @spec get(String.t(), String.t()) :: {:ok, Perimeter.t()} | {:error, get_error()}
  def get(path, perimeter_id) do
    case list(path) do
      {:ok, perimeters} ->
        case Enum.find(perimeters, &(&1.id == perimeter_id)) do
          nil -> {:error, :not_found}
          found -> {:ok, found}
        end

      {:error, _} = err ->
        err
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_path do
    System.get_env("DR_PERIMETERS_PATH", @default_path)
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, _reason} -> {:error, :file_not_found}
    end
  end

  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :malformed}
    end
  end

  defp validate_and_cast(decoded) when is_list(decoded) do
    decoded
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, idx}, {:ok, acc} ->
      case cast_entry(entry, idx) do
        {:ok, perimeter} -> {:cont, {:ok, [perimeter | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      err -> err
    end
  end

  defp validate_and_cast(_), do: {:error, :malformed}

  defp cast_entry(entry, _idx) when is_map(entry) do
    with {:ok, id} <- fetch_string(entry, "id"),
         {:ok, host} <- fetch_string(entry, "host"),
         {:ok, apps} <- fetch_string_list(entry, "apps"),
         {:ok, canary} <- fetch_boolean(entry, "canary") do
      archive_age = Map.get(entry, "archiveAgeDaysMax")

      if valid_optional_integer?(archive_age) do
        {:ok,
         %Perimeter{
           id: id,
           host: host,
           apps: apps,
           canary: canary,
           archive_age_days_max: archive_age
         }}
      else
        {:error, :malformed}
      end
    end
  end

  defp cast_entry(_, _), do: {:error, :malformed}

  defp fetch_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, val} when is_binary(val) -> {:ok, val}
      {:ok, _} -> {:error, :malformed}
      :error -> {:error, :malformed}
    end
  end

  defp fetch_string_list(map, key) do
    case Map.fetch(map, key) do
      {:ok, val} when is_list(val) ->
        if Enum.all?(val, &is_binary/1) do
          {:ok, val}
        else
          {:error, :malformed}
        end

      {:ok, _} ->
        {:error, :malformed}

      :error ->
        {:error, :malformed}
    end
  end

  defp fetch_boolean(map, key) do
    case Map.fetch(map, key) do
      {:ok, val} when is_boolean(val) -> {:ok, val}
      {:ok, _} -> {:error, :malformed}
      :error -> {:error, :malformed}
    end
  end

  defp valid_optional_integer?(nil), do: true
  defp valid_optional_integer?(v) when is_integer(v) and v > 0, do: true
  defp valid_optional_integer?(_), do: false
end
