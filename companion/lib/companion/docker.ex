defmodule Companion.Docker do
  @moduledoc false

  @type container_id :: String.t()
  @type opts :: keyword()

  @doc """
  Docker Engine API surface used by the companion. HTTP and CLI adapters implement this;
  tests use `Companion.Docker.Mock`.
  """
  @callback version() :: {:ok, map()} | {:error, term()}
  @callback container_inspect(container_id()) :: {:ok, map()} | {:error, term()}
  @callback container_list(opts()) :: {:ok, [map()]} | {:error, term()}
  @callback container_create(attrs :: map()) :: {:ok, container_id()} | {:error, term()}
  @callback container_start(container_id(), opts()) :: :ok | {:error, term()}
  @callback container_stop(container_id(), opts()) :: :ok | {:error, term()}
  @callback container_remove(container_id(), opts()) :: :ok | {:error, term()}
  @callback container_pause(container_id()) :: :ok | {:error, term()}
  @callback container_unpause(container_id()) :: :ok | {:error, term()}
  @callback container_stats(container_id()) :: {:ok, map()} | {:error, term()}
  @callback container_exec(container_id(), cmd :: [String.t()], opts()) ::
              {:ok, String.t()} | {:error, term()}

  @callback container_exec_with_exit(container_id(), cmd :: [String.t()], opts()) ::
              {:ok, %{stdout: String.t(), exit_code: integer()}} | {:error, term()}
  @callback image_list(opts()) :: {:ok, [map()]} | {:error, term()}
  @callback image_pull(ref :: String.t()) :: :ok | {:error, term()}

  @doc false
  def impl do
    Application.get_env(:companion, :docker_adapter, Companion.Docker.Mock)
  end
end
