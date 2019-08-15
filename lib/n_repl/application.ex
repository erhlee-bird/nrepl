defmodule NRepl.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      :poolboy.child_spec(:worker, poolboy_config())
    ]

    opts = [strategy: :one_for_one, name: NRepl.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp poolboy_config do
    [
      {:name, {:local, :worker}},
      {:worker_module, NRepl.Worker},
      {:size, 5},
      {:max_overflow, 2}
    ]
  end
end
