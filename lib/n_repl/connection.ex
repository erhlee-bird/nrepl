defmodule NRepl.Connection do
  alias NRepl.Message
  require Logger
  use Connection

  # Public API.

  def start_link(args, options \\ []) do
    [host, port, session_id] =
      case args do
        [host, port] -> [host, port, nil]
        [_host, _port, _session_id] = ok -> ok
        # Raise errors for other unexpected args.
        _ -> raise ArgumentError, message:
          "#{__MODULE__}.start_link requires at least a `[host, port]` args list."
      end

    Connection.start_link(
      __MODULE__,
      %{
        host: host || "127.0.0.1",
        port: port,
        opts: [],
        session_id: session_id,
        socket: nil
      },
      options
    )
  end

  def close(pid), do: Connection.call(pid, :close)
  def port_get(pid), do: Connection.call(pid, :port_get)
  def port_set(pid, port), do: Connection.call(pid, {:port_set, port})

  @spec send_msg(pid(), atom() | String.t(), map()) :: Enum.t()

  def send_msg(pid, op, opts \\ %{}) do
    Connection.call(pid, {:send_msg, op, opts})
  end

  def set_session_id(pid, session_id) do
    Connection.call(pid, {:set_session_id, session_id})
  end

  # Utility functions.

  defp bencode_response({_op, nil, _}) do
    # Use a nil socket as a sentinel to halt the stream.
    {:halt, nil}
  end

  defp bencode_response({op, socket, buffer}) do
    # First try and decode results out of the buffer.
    case Bento.decode_some(buffer) do
      {:ok, data, new_buffer} ->
        # If the data contains a `:done` status, we can halt.
        done? =
          data
          |> Map.get("status", [])
          |> Enum.any?(fn x -> x == "done" end)

        if done? do
          {[data], {op, nil, new_buffer}}
        else
          {[data], {op, socket, new_buffer}}
        end

      # If the buffer is incomplete, read more data off the wire.
      _ ->
        case :gen_tcp.recv(socket, 0) do
          {:ok, bytes} ->
            {[], {op, socket, concat_bytes(buffer, bytes)}}

          {:error, reason} ->
            Logger.error("nREPL #{inspect(op)} encountered stream read error: #{inspect(reason)}")
            {:halt, socket}
        end
    end
  end

  defp bencode_response_stream(op, socket) do
    Stream.resource(
      # The stream keeps a socket and a buffer for incomplete parsed data.
      fn -> {op, socket, []} end,
      # Repeatedly read and produce Bencode data entries.
      &bencode_response/1,
      # Connection state is handled separately from this call.
      fn socket -> socket end
    )
  end

  defp concat_bytes(buffer, bytes) when is_binary(buffer), do: buffer <> bytes
  defp concat_bytes(buffer, bytes), do: buffer ++ [bytes]

  defp establish_session(socket) do
    # An nREPL client needs to establish a session and save away the session id for
    # future interactions with the nREPL server.

    # Per nREPL documentation for building clients, the interaction goes as follows:

    # * Client sends `clone` to create a new session
    # * Server responds with the session id
    # * Client sends `describe` to check the server's capabilities and version/
    #   runtime information.
    # * Server responds with a map of the relevant data.
    # * Client starts sending `eval` messages using the session id that it obtained
    #   earlier.
    # * Server responds with the appropriate messages (e.g. `value` and `out`).
    #   Eventually a message with status `done` signals that the eval message has
    #   been fully processed.
    :ok = :gen_tcp.send(socket, Message.clone())

    response =
      bencode_response_stream(:clone, socket)
      |> Enum.to_list()
      |> List.first(%{})

    Map.get(response, "new-session", nil)
  end

  def to_safe_existing_atom(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> value
    end
  end

  # Connection callbacks.

  @impl true
  def init(state), do: {:connect, nil, state}

  @impl true
  def connect(_info, %{host: host, port: port, opts: opts, session_id: session_id} = state) do
    conn_timeout = Keyword.get(opts, :timeout, :infinity)
    tcp_opts = [{:active, false}, :binary]

    {socket, session_id} =
      case :gen_tcp.connect(to_charlist(host), port, tcp_opts, conn_timeout) do
        {:ok, socket} ->
          if session_id != nil do
            {socket, session_id}
          else
            {socket, establish_session(socket)}
          end

        {:error, reason} ->
          Logger.error("nREPL connect error: #{inspect(reason)}")
          {nil, nil}
      end

    if session_id != nil do
      Logger.debug("nREPL session alive: #{session_id}")
      {:ok, %{state | session_id: session_id, socket: socket}}
    else
      {:backoff, 1000, state}
    end
  end

  @impl true
  def disconnect(info, %{socket: nil} = state) do
    case info do
      {:close, from} ->
        Connection.reply(from, :ok)

      _ ->
        :ok
    end

    {:connect, :reconnect, %{state | session_id: nil, socket: nil}}
  end

  @impl true
  def disconnect(info, %{socket: socket} = state) do
    :ok = :gen_tcp.close(socket)

    case info do
      {:close, from} ->
        Connection.reply(from, :ok)

      {:error, :closed} ->
        :error_logger.format("Connection closed~n", [])

      {:error, reason} ->
        reason = :inet.format_error(reason)
        :error_logger.format("Connection error: ~s~n", [reason])
    end

    {:connect, :reconnect, %{state | session_id: nil, socket: nil}}
  end

  def handle_call(:port_get, _, %{port: port} = state) do
    {:reply, port, state}
  end

  def handle_call({:port_set, port}, from, state) do
    # Update the state to a new port and trigger a reconnect.
    {:disconnect, {:close, from}, %{state | port: port}}
  end

  @impl true
  def handle_call(_, _, %{socket: nil} = state) do
    {:reply, {:error, :closed}, state}
  end

  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call({:send_msg, op, opts}, _, %{session_id: session_id, socket: socket} = state) do
    # Dynamically call the corresponding op message function.
    encoded_msg =
      apply(
        :"Elixir.NRepl.Message",
        to_safe_existing_atom(op),
        [
          opts
          |> Map.put_new_lazy(:session, fn -> session_id end)
        ]
      )

    :ok = :gen_tcp.send(socket, encoded_msg)

    # Return a stream of decoded bencode objects.
    {:reply, bencode_response_stream(op, socket), state}
  end

  def handle_call({:set_session_id, session_id}, _, state) do
    Logger.debug("nREPL changing session id: #{state.session_id} -> #{session_id}")
    {:reply, :ok, %{state | session_id: session_id}}
  end
end
