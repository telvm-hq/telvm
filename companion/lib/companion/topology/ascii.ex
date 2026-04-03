defmodule Companion.Topology.Ascii do
  @moduledoc false

  @card_width 22
  @max_name 14
  @compose_project "telvm"
  @network "telvm_default"
  @host_port 4000
  @lab_dns_alias "telvm-lab-workload"
  @box_w 38

  @doc """
  Single scrollable blueprint: Compose bridge + companion (Phoenix + API) + db/vm_node,
  then spine + lab VM cards (same data as Warm assets), then signals.

  `stack_snapshot` is `{:ok, [map()]}` with keys `:service`, `:name`, `:state`, `:id`
  or `{:error, :unavailable}`.
  """
  def warm_blueprint(warm_machines, stack_snapshot) when is_list(warm_machines) do
    hostname = System.get_env("HOSTNAME", "")

    [
      header_band(),
      stack_rows(stack_snapshot, hostname),
      connector_to_labs(),
      lab_section(warm_machines),
      signals_block()
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp header_band do
    """
    === Network blueprint · #{@compose_project} · bridge #{@network} ===
    Embedded DNS on this bridge resolves service names (db, vm_node, #{@lab_dns_alias}, …).
    From the host, only companion publishes :#{@host_port} → LiveView + REST /telvm/api (JSON, SSE).
    Lab rows below mirror this tab; discovery uses Engine HTTP over docker.sock (not Docker CLI).
    """
    |> String.trim()
  end

  defp stack_rows({:error, :unavailable}, _hostname) do
    "(Compose stack: Engine container list unavailable — when Compose is up you should see companion, db, vm_node.)"
  end

  defp stack_rows({:ok, items}, hostname) when is_list(items) do
    by_svc =
      items
      |> Enum.map(fn i -> {i.service, i} end)
      |> Map.new()

    top_note =
      if items == [] do
        "(No containers with label com.docker.compose.project=#{@compose_project} — is Compose running?)\n"
      else
        ""
      end

    top_note <>
      row_three_boxes(
        box_companion(Map.get(by_svc, "companion"), hostname),
        box_service(Map.get(by_svc, "db"), "db", "Postgres"),
        box_service(Map.get(by_svc, "vm_node"), "vm_node", "sandbox :3333")
      )
  end

  defp row_three_boxes(left, mid, right) do
    l_lines = String.split(left, "\n")
    m_lines = String.split(mid, "\n")
    r_lines = String.split(right, "\n")
    h = max(max(length(l_lines), length(m_lines)), length(r_lines))
    l_lines = pad_box_lines(l_lines, h)
    m_lines = pad_box_lines(m_lines, h)
    r_lines = pad_box_lines(r_lines, h)

    0..(h - 1)//1
    |> Enum.map(fn i ->
      String.pad_trailing(Enum.at(l_lines, i), @box_w) <>
        "  " <>
        String.pad_trailing(Enum.at(m_lines, i), @box_w) <>
        "  " <>
        String.pad_trailing(Enum.at(r_lines, i), @box_w)
    end)
    |> Enum.join("\n")
  end

  defp pad_box_lines(lines, h) do
    lines = lines ++ List.duplicate("", h - length(lines))

    Enum.map(lines, fn line ->
      String.slice(String.pad_trailing(line, @box_w), 0, @box_w)
    end)
  end

  defp box_companion(nil, _hostname) do
    """
    ┌companion (Phoenix)─────────────────┐
    │ LiveView UI · GET /telvm/api       │
    │ :#{@host_port} published to host    │
    │ docker.sock -> Engine API          │
    │ (not listed)                       │
    └────────────────────────────────────┘
    """
    |> String.trim_trailing()
  end

  defp box_companion(%{state: st, name: name, id: id}, hostname) do
    n = String.slice(name || "", 0, 16)
    line = String.slice("#{st} · #{n}", 0, 34)

    base =
      """
      ┌companion (Phoenix)─────────────────┐
      │ LiveView UI · GET /telvm/api       │
      │ :#{@host_port} published to host    │
      │ docker.sock -> Engine API          │
      │ #{String.pad_trailing(line, 34)} │
      └────────────────────────────────────┘
      """

    annotate_this_beam(String.trim_trailing(base), hostname, id)
  end

  defp annotate_this_beam(s, hostname, id) when is_binary(id) and id != "" do
    short = String.slice(id, 0, 12)

    if hostname != "" and (short == hostname or String.starts_with?(id, hostname)) do
      String.replace(
        s,
        "└────────────────────────────────────┘",
        "│ (this BEAM process)                │\n└────────────────────────────────────┘"
      )
    else
      s
    end
  end

  defp annotate_this_beam(s, _, _), do: s

  defp box_service(nil, dns, role) do
    """
    ┌#{String.slice(String.pad_trailing(dns, 16), 0, 16)}──────────────────┐
    │ DNS name: #{String.pad_trailing(dns, 27)} │
    │ #{String.pad_trailing(role, 34)} │
    │ (not listed)                       │
    └────────────────────────────────────┘
    """
    |> String.trim_trailing()
  end

  defp box_service(%{state: st, name: name}, dns, role) do
    n = String.slice(name || "", 0, 14)
    line = String.slice("#{st} · #{n}", 0, 34)

    """
    ┌#{String.slice(String.pad_trailing(dns, 16), 0, 16)}──────────────────┐
    │ DNS name: #{String.pad_trailing(dns, 27)} │
    │ #{String.pad_trailing(role, 34)} │
    │ #{String.pad_trailing(line, 34)} │
    └────────────────────────────────────┘
    """
    |> String.trim_trailing()
  end

  defp connector_to_labs do
    """
              │
              ▼  telvm.vm_manager_lab=true (labs on #{@network}; workload alias #{@lab_dns_alias})
    """
    |> String.trim()
  end

  defp lab_section(machines) do
    case machines do
      [] ->
        "(no lab containers yet — Verify on Machines)"

      _ ->
        machines
        |> Enum.map(&card_lines/1)
        |> Enum.chunk_every(5)
        |> Enum.map(&merge_cards_horizontal/1)
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {block, idx} ->
          if idx == 0 do
            block
          else
            "              │\n              ▼\n" <> block
          end
        end)
    end
  end

  defp signals_block do
    """
    --- signals ----------------------------------------------------------
    """ <> signals_static()
  end

  @doc false
  def signals_static do
    """
    * docker compose down: "Network #{@network} Resource is still in use"
      A container is still attached (often a lab). Try: docker network inspect #{@network}
    """
    |> String.trim()
  end

  defp card_lines(m) do
    name = m |> Map.get(:name, "") |> to_string() |> String.slice(0, @max_name)
    st = m |> Map.get(:status, "?") |> to_string() |> String.slice(0, 4) |> String.pad_trailing(4)
    img = m |> Map.get(:image, "") |> to_string() |> String.slice(0, 12)

    pub =
      case Map.get(m, :ports, []) do
        ps when is_list(ps) and ps != [] ->
          ps |> Enum.map(fn p -> ":#{p}" end) |> Enum.join(" ")

        _ ->
          "—"
      end

    int =
      case Map.get(m, :internal_ports, []) do
        ps when is_list(ps) and ps != [] ->
          ps |> Enum.take(2) |> Enum.map(fn p -> "i#{p}" end) |> Enum.join(" ")

        _ ->
          ""
      end

    int_line = if int == "", do: " ", else: int

    inner = [
      " #{String.pad_trailing(name, @max_name)} ",
      " #{st} #{img} ",
      " #{pub} ",
      " #{int_line} "
    ]

    top = "┌" <> String.duplicate("─", @card_width - 2) <> "┐"
    mid = Enum.map(inner, fn line -> "│" <> String.pad_trailing(line, @card_width - 2) <> "│" end)
    bot = "└" <> String.duplicate("─", @card_width - 2) <> "┘"

    [top | mid] ++ [bot]
  end

  defp merge_cards_horizontal(cards) when is_list(cards) do
    max_h = cards |> Enum.map(&length/1) |> Enum.max()
    padded = Enum.map(cards, fn lines -> pad_height(lines, max_h) end)

    0..(max_h - 1)//1
    |> Enum.map(fn i ->
      padded
      |> Enum.map(fn lines -> Enum.at(lines, i) |> String.pad_trailing(@card_width) end)
      |> Enum.join("  ")
    end)
    |> Enum.join("\n")
  end

  defp pad_height(lines, h) do
    pad = h - length(lines)

    if pad <= 0 do
      lines
    else
      lines ++ Enum.map(1..pad//1, fn _ -> String.duplicate(" ", @card_width) end)
    end
  end
end
