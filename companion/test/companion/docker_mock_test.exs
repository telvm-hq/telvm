defmodule Companion.DockerMockTest do
  use ExUnit.Case, async: true

  alias Companion.Docker.Mock, as: DockerMock

  describe "Companion.Docker.Mock implements the behaviour" do
    test "version/0" do
      assert {:ok, %{"Version" => "mock"}} = DockerMock.version()
    end

    test "container_inspect/1 happy path" do
      assert {:ok, %{"State" => %{"Status" => "running"}}} = DockerMock.container_inspect("any")
    end

    test "container_inspect/1 error branch" do
      assert {:error, :mock_error} = DockerMock.container_inspect("__error__")
    end

    test "container_list/1" do
      assert {:ok, []} = DockerMock.container_list([])
    end

    test "container_create/1" do
      assert {:ok, "mock_container_id"} = DockerMock.container_create(%{})
    end

    test "container_start/2" do
      assert :ok = DockerMock.container_start("id", [])
    end

    test "container_stop/2 error branch" do
      assert {:error, :mock_error} = DockerMock.container_stop("__error__", [])
    end

    test "container_stop/2 happy path" do
      assert :ok = DockerMock.container_stop("id", [])
    end

    test "container_remove/2" do
      assert :ok = DockerMock.container_remove("id", [])
    end

    test "container_pause/1" do
      assert :ok = DockerMock.container_pause("id")
    end

    test "container_pause/1 error branch" do
      assert {:error, :mock_error} = DockerMock.container_pause("__error__")
    end

    test "container_unpause/1" do
      assert :ok = DockerMock.container_unpause("id")
    end

    test "container_unpause/1 error branch" do
      assert {:error, :mock_error} = DockerMock.container_unpause("__error__")
    end

    test "container_stats/1" do
      assert {:ok, %{}} = DockerMock.container_stats("id")
    end

    test "image_list/1" do
      assert {:ok, []} = DockerMock.image_list([])
    end
  end

  describe "Companion.Docker.impl/0" do
    test "defaults to the mock adapter" do
      assert Companion.Docker.impl() == Companion.Docker.Mock
    end
  end
end
