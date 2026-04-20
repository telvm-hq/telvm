defmodule Slackeel.Preflight.DiskLocal do
  @moduledoc false

  @min_capacity_kb 500_000

  @doc """
  Returns disk rows from Erlang **`:disksup`** and an effective free-space floor (bytes)
  used for conservative preflight: minimum available among "large" volumes.

  On Linux containers, **`:disksup`** often returns no rows; we then fall back to **`df -Pk /`**
  so Pre-flight still works in Docker.
  """
  def snapshot do
    _ = Application.ensure_all_started(:os_mon)

    case snapshot_from_disksup() do
      {:ok, _} = ok ->
        ok

      {:error, :no_disk_data} ->
        snapshot_from_df_unix_root()
    end
  end

  defp snapshot_from_disksup do
    rows =
      :disksup.get_disk_data()
      |> Enum.map(&normalize_row/1)
      |> Enum.reject(&is_nil/1)

    candidate_rows =
      case Enum.filter(rows, fn r -> r.capacity_kb >= @min_capacity_kb end) do
        [] -> rows
        big -> big
      end

    case Enum.min_by(candidate_rows, & &1.available_kb, fn -> nil end) do
      nil ->
        {:error, :no_disk_data}

      r ->
        {:ok,
         %{
           origin: :local_beam,
           effective_free_bytes: r.available_kb * 1024,
           disks: rows
         }}
    end
  end

  defp snapshot_from_df_unix_root do
    case :os.type() do
      {:unix, _} -> df_pk_root_snapshot()
      _ -> {:error, :no_disk_data}
    end
  end

  defp df_pk_root_snapshot do
    case System.cmd("df", ["-Pk", "/"], stderr_to_stdout: true) do
      {out, 0} ->
        parse_df_pk_output(out)

      _ ->
        {:error, :no_disk_data}
    end
  end

  defp parse_df_pk_output(out) do
    lines =
      out
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "Filesystem"))

    case lines do
      [line] ->
        parts = String.split(line, ~r/\s+/, trim: true)

        case parts do
          [_fs, _blocks, _used, avail | _] ->
            case Integer.parse(avail) do
              {kb, _} when kb >= 0 ->
                {:ok,
                 %{
                   origin: :local_beam,
                   effective_free_bytes: kb * 1024,
                   disks: [
                     %{id: "/", capacity_kb: kb, available_kb: kb}
                   ]
                 }}

              _ ->
                {:error, :no_disk_data}
            end

          _ ->
            {:error, :no_disk_data}
        end

      _ ->
        {:error, :no_disk_data}
    end
  end

  defp normalize_row({id, kb_cap, kb_avail}) when is_integer(kb_cap) and is_integer(kb_avail) do
    id_str = id |> to_string()

    %{
      id: id_str,
      capacity_kb: kb_cap,
      available_kb: kb_avail
    }
  end

  defp normalize_row(_), do: nil
end
