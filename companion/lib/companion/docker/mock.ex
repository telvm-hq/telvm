defmodule Companion.Docker.Mock do
  @moduledoc false
  @behaviour Companion.Docker

  @impl true
  def version, do: {:ok, %{"Version" => "mock"}}

  @impl true
  def container_inspect("__error__"), do: {:error, :mock_error}
  def container_inspect(_id), do: {:ok, %{"Id" => "mock", "State" => %{"Status" => "running"}}}

  @impl true
  def container_list(_opts), do: {:ok, []}

  @impl true
  def container_create(_attrs), do: {:ok, "mock_container_id"}

  @impl true
  def container_start(_id, _opts), do: :ok

  @impl true
  def container_stop("__error__", _opts), do: {:error, :mock_error}
  def container_stop(_id, _opts), do: :ok

  @impl true
  def container_restart("__error__", _opts), do: {:error, :mock_error}
  def container_restart("__not_found__", _opts), do: {:error, :not_found}
  def container_restart(_id, _opts), do: :ok

  @impl true
  def container_remove(_id, _opts), do: :ok

  @impl true
  def container_pause("__not_found__"), do: {:error, :not_found}
  def container_pause("__error__"), do: {:error, :mock_error}
  def container_pause(_id), do: :ok

  @impl true
  def container_unpause("__not_found__"), do: {:error, :not_found}
  def container_unpause("__error__"), do: {:error, :mock_error}
  def container_unpause(_id), do: :ok

  @impl true
  def container_stats("__error__"), do: {:error, :mock_error}
  def container_stats("__not_found__"), do: {:error, :not_found}

  def container_stats(_id) do
    {:ok,
     %{
       "cpu_stats" => %{
         "cpu_usage" => %{"total_usage" => 100_000_000_000},
         "system_cpu_usage" => 500_000_000_000,
         "online_cpus" => 2
       },
       "precpu_stats" => %{
         "cpu_usage" => %{"total_usage" => 99_000_000_000},
         "system_cpu_usage" => 499_000_000_000
       },
       "memory_stats" => %{"usage" => 128_000_000, "limit" => 1_073_741_824},
       "networks" => %{"eth0" => %{"rx_bytes" => 1000, "tx_bytes" => 2000}}
     }}
  end

  @impl true
  def container_logs("__error__", _opts), do: {:error, :mock_error}
  def container_logs("__not_found__", _opts), do: {:error, :not_found}

  def container_logs(_id, _opts) do
    {:ok, "2024-01-01T00:00:00.000000000Z mock log line stdout\n"}
  end

  @impl true
  def container_exec(_id, ["cat", "/proc/net/tcp", "/proc/net/tcp6"], _opts) do
    # Simulate a container with an IPv4 listener on port 3333 (tcp) and an
    # IPv6 dual-stack listener on port 3333 (tcp6) — mirrors go-http-lab on Alpine.
    tcp =
      "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n" <>
        "   0: 00000000:0D05 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12345 1 0000000000000000 100 0 0 10 0\n"

    tcp6 =
      "  sl  local_address                         remote_address                    st\n" <>
        "   0: 00000000000000000000000000000000:0D05 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12346 1 0000000000000000 100 0 0 10 0\n"

    {:ok, tcp <> tcp6}
  end

  def container_exec(_id, _cmd, _opts), do: {:ok, ""}

  @impl true
  def container_exec_with_exit(_id, _cmd, _opts) do
    {:ok, %{stdout: "", exit_code: 0}}
  end

  @impl true
  def image_list(_opts), do: {:ok, []}

  @impl true
  def image_pull(_ref), do: :ok
end
