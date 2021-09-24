defmodule NRepl.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    host = System.get_env("NREPL_HOST")

    port =
      System.get_env("NREPL_PORT")
      |> Integer.parse()
      |> elem(0)

    children = [
      :poolboy.child_spec(:worker, poolboy_config(), [host, port])
    ]

    opts = [strategy: :one_for_one, name: NRepl.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def pool_name, do: :nrepl

  defp poolboy_config do
    [
      {:name, {:local, NRepl.Application.pool_name()}},
      {:worker_module, NRepl.Connection},
      {:size, 1},
      {:max_overflow, 0}
    ]
  end
end
