defmodule Companion.Morayeel.StorageState do
  @moduledoc false

  @doc """
  Summarizes Playwright `storageState.json` for LiveView (no cookie values).
  """
  @spec summarize_from_path(String.t()) :: map()
  def summarize_from_path(path) when is_binary(path) do
    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, json} -> summarize(json)
          {:error, _} -> empty_summary(:invalid_json)
        end

      {:error, _} ->
        empty_summary(:missing_file)
    end
  end

  @spec summarize(map()) :: map()
  def summarize(%{"cookies" => cookies}) when is_list(cookies) do
    names = cookies |> Enum.map(&cookie_name/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    origins = cookies |> Enum.map(&cookie_domain/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    %{
      cookie_count: length(cookies),
      cookie_names: names,
      origins: origins
    }
  end

  def summarize(_), do: empty_summary(:unexpected_shape)

  defp empty_summary(reason) do
    %{
      cookie_count: 0,
      cookie_names: [],
      origins: [],
      note: to_string(reason)
    }
  end

  defp cookie_name(%{"name" => n}) when is_binary(n), do: n
  defp cookie_name(_), do: nil

  defp cookie_domain(%{"domain" => d}) when is_binary(d), do: d
  defp cookie_domain(_), do: nil
end
