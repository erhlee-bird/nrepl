defmodule NRepl.Message do
  @moduledoc """
  See the Supported nREPL operations page.

    * https://nrepl.org/nrepl/ops.html
  """

  # Middleware.

  def maybe_generate_id(data) do
    data
    |> Map.put_new_lazy(:id, &UUID.uuid4/0)
  end

  def default_middleware do
    [
      &maybe_generate_id/1,
      &Bento.encode!/1
    ]
  end

  defp run_middleware(data, middleware \\ default_middleware()) do
    middleware
    |> Enum.reduce(data, fn m, acc -> m.(acc) end)
  end

  # Message API.

  def clone(opts \\ %{}) do
    opts
    |> Map.put(:op, "clone")
    |> run_middleware()
  end

  def close(opts \\ %{}) do
    opts
    |> Map.put(:op, "close")
    |> run_middleware()
  end

  def describe(opts \\ %{}) do
    opts
    |> Map.put(:op, "describe")
    |> Map.put_new_lazy(:verbose?, fn -> true end)
    |> run_middleware()
  end

  def eval(opts \\ %{}) do
    opts
    |> Map.put(:op, "eval")
    |> run_middleware()
  end

  def interrupt(opts \\ %{}) do
    opts
    |> Map.put(:op, "interrupt")
    |> run_middleware()
  end

  def lookup(opts \\ %{}) do
    opts
    |> Map.put(:op, "lookup")
    |> run_middleware()
  end

  def ls_sessions(opts \\ %{}) do
    opts
    |> Map.put(:op, "ls-sessions")
    |> run_middleware()
  end
end
