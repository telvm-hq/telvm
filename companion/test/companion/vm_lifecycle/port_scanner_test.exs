defmodule Companion.VmLifecycle.PortScannerTest do
  use ExUnit.Case, async: true

  alias Companion.VmLifecycle.PortScanner

  describe "parse_proc_net_tcp/1" do
    test "parses single listening port" do
      input = """
        sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
         0: 00000000:0D05 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12345 1 0000000000000000 100 0 0 10 0
      """

      assert PortScanner.parse_proc_net_tcp(input) == [3333]
    end

    test "parses multiple listening ports" do
      input = """
        sl  local_address rem_address   st tx_queue rx_queue
         0: 00000000:0D05 00000000:0000 0A 00000000:00000000
         1: 00000000:0BB8 00000000:0000 0A 00000000:00000000
         2: 00000000:1F90 00000000:0000 0A 00000000:00000000
      """

      assert PortScanner.parse_proc_net_tcp(input) == [3000, 3333, 8080]
    end

    test "filters out non-LISTEN connections (state != 0A)" do
      input = """
        sl  local_address rem_address   st tx_queue rx_queue
         0: 00000000:0D05 00000000:0000 0A 00000000:00000000
         1: 0100007F:C350 0100007F:0D05 01 00000000:00000000
         2: 00000000:1F90 00000000:0000 06 00000000:00000000
      """

      assert PortScanner.parse_proc_net_tcp(input) == [3333]
    end

    test "returns empty list for empty output" do
      assert PortScanner.parse_proc_net_tcp("") == []
    end

    test "returns empty list for header-only output" do
      input = "  sl  local_address rem_address   st tx_queue rx_queue\n"
      assert PortScanner.parse_proc_net_tcp(input) == []
    end

    test "deduplicates ports" do
      input = """
        sl  local_address rem_address   st tx_queue rx_queue
         0: 00000000:0D05 00000000:0000 0A 00000000:00000000
         1: 0100007F:0D05 00000000:0000 0A 00000000:00000000
      """

      assert PortScanner.parse_proc_net_tcp(input) == [3333]
    end

    test "scan_ports uses mock adapter" do
      assert {:ok, [3333]} = PortScanner.scan_ports("any_container_id")
    end
  end
end
