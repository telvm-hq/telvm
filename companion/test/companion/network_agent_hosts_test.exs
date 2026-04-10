defmodule Companion.NetworkAgentHostsTest do
  use ExUnit.Case, async: true

  alias Companion.NetworkAgentHosts

  describe "normalize/1" do
    test "nil -> []" do
      assert NetworkAgentHosts.normalize(nil) == []
    end

    test "empty list -> []" do
      assert NetworkAgentHosts.normalize([]) == []
    end

    test "list of host maps -> unchanged (same elements)" do
      hosts = [%{"ip" => "10.0.0.1", "mac" => "aa-bb"}, %{"ip" => "10.0.0.2"}]
      assert NetworkAgentHosts.normalize(hosts) == hosts
    end

    test "empty map (JSON object) -> []" do
      assert NetworkAgentHosts.normalize(%{}) == []
    end

    test "non-empty map without ip key -> []" do
      assert NetworkAgentHosts.normalize(%{"foo" => "bar"}) == []
    end

    test "single host as object -> one-element list" do
      host = %{"ip" => "192.168.137.2", "mac" => "11-22-33"}
      assert NetworkAgentHosts.normalize(host) == [host]
    end

    test "list drops non-map entries" do
      assert NetworkAgentHosts.normalize([%{"ip" => "1.1.1.1"}, "bad", nil]) == [
               %{"ip" => "1.1.1.1"}
             ]
    end

    test "atoms and strings -> []" do
      assert NetworkAgentHosts.normalize("hosts") == []
      assert NetworkAgentHosts.normalize(:ok) == []
    end
  end
end
