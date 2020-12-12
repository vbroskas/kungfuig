defmodule Kungfuig.Test do
  use ExUnit.Case, async: false
  doctest Kungfuig

  test "custom target" do
    {:ok, pid} =
      Kungfuig.Supervisor.start_link(
        blender: {Kungfuig.Blender, interval: 100, callback: {self(), {:info, :updated}}}
      )

    assert_receive {:updated, %{env: %{kungfuig: []}}}, 110

    Application.put_env(:kungfuig, :foo, 42)
    assert_receive {:updated, %{env: %{kungfuig: [foo: 42]}}}, 1_010

    System.put_env("KUNGFUIG_FOO", "42")
    assert_receive {:updated, %{system: %{"KUNGFUIG_FOO" => "42"}}}, 1_010

    assert Kungfuig.config() == %{env: %{kungfuig: [foo: 42]}, system: %{"KUNGFUIG_FOO" => "42"}}

    Application.delete_env(:kungfuig, :foo)
    Supervisor.stop(pid)
  end

  test "transform/1" do
    {:ok, pid} =
      Kungfuig.Supervisor.start_link(
        workers: [
          {Kungfuig.Backends.EnvTransform, interval: 100, callback: {self(), {:info, :updated}}}
        ]
      )

    assert_receive {:updated, %{env_transform: []}}, 110

    Application.put_env(:kungfuig, :foo_transform, %{bar: :baz})
    assert_receive {:updated, %{env_transform: [foo_transform: :baz]}}, 1_010

    assert Kungfuig.config() == %{env_transform: [foo_transform: :baz]}

    Application.delete_env(:kungfuig, :foo_transform)
    Supervisor.stop(pid)
  end
end
