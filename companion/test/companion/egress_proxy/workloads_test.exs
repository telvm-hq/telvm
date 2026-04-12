defmodule Companion.EgressProxy.WorkloadsTest do
  use ExUnit.Case, async: true

  alias Companion.EgressProxy.Workloads

  test "parse_json skips invalid rows" do
    json = ~s([
      {"id": "a", "port": 4001, "allow_hosts": ["x.com"]},
      {"id": "", "port": 4002, "allow_hosts": []},
      {"id": "bad", "port": 99999, "allow_hosts": []}
    ])

    rows = Workloads.parse_json(json)
    assert length(rows) == 1
    assert hd(rows).id == "a"
    assert hd(rows).port == 4001
    assert hd(rows).allow_hosts == ["x.com"]
  end

  test "attach_secrets reads authorization_env" do
    System.put_env("TELVM_EGRESS_TEST_AUTH", "Bearer test")

    on_exit(fn -> System.delete_env("TELVM_EGRESS_TEST_AUTH") end)

    rows =
      [%{id: "w", port: 1, allow_hosts: [], authorization_env: "TELVM_EGRESS_TEST_AUTH"}]
      |> Workloads.attach_secrets()

    assert hd(rows).inject_authorization == "Bearer test"
  end
end
