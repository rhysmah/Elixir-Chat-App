defmodule Chat.Proxy do
  @moduledoc """
  Handles incoming TCP connections from clients, interprets commands,
  and communicates with the Chat.Server to manage nicknames and relay messages.
  """

  @valid_nickname_characters Enum.concat([
                               # numbers (0 - 9)
                               Enum.to_list(48..57),
                               # uppercase letters (A - Z)
                               Enum.to_list(65..90),
                               # lowercase letters (a - z)
                               Enum.to_list(97..122),
                               # underscore (_)
                               [95]
                             ])

  #######################
  # CONNECT WITH CLIENT #
  #######################

  @doc """
  Starts listening for incoming TCP connections on the specified port.
  Spawns a new process for each connection to handle client-server communication.

  ## Parameters:
  - port: The port number to listen on, defaults to 6666.

  ## Examples:
      iex> Chat.Proxy.start(6666)
  """
  def start(port \\ 6666) do
    options = [:binary, packet: :line, reuseaddr: true]
    {:ok, listening_socket} = :gen_tcp.listen(port, options)
    spawn(fn -> create_client_connection(listening_socket) end)
    IO.puts("Listening at Port #{port}...")
  end

  @doc false
  defp create_client_connection(listening_socket) do
    {:ok, client_socket} = :gen_tcp.accept(listening_socket)

    IO.puts("Connection established.")
    IO.puts("Listening for clients...")

    # Immediately begin listening for other client requests.
    spawn(fn -> create_client_connection(listening_socket) end)
    IO.puts("#{inspect(self())}: start serving #{inspect(client_socket)}")

    # Spawn a process for proxy-client communication; this is
    # how the proxy and client will send messages bi-laterally.
    route_client_request(client_socket)
  end

  ###########################
  # PROCESS CLIENT REQUESTS #
  ###########################

  defp route_client_request(client_socket) do
    # Proxy receives replies from server and other proxies
    receive do
      # (1) Receive messages from server
      {:tcp, _socket, data} ->
        sanitized_data = String.trim(data)

        # Handles all commands, valid and invalid, via helper functions
        handle_client_commands(sanitized_data, client_socket)

      # (2) Receive messages from other clients
      {:message, sender_nickname, message} ->
        :gen_tcp.send(client_socket, "#{inspect(sender_nickname)} said: #{message}\n")

      # (3) Client closed connection
      {:tcp_closed, _socket} ->
        GenServer.call({:global, Chat.Server}, {:remove_user, self()})
    end

    # Continue listening for additional requests
    route_client_request(client_socket)
  end

  ####################
  # HELPER FUNCTIONS #
  ####################

  defp handle_message_command(client_socket, recipients_string, message) do
    recipients = String.split(recipients_string, ",")
    message = String.trim(message)

    case GenServer.call({:global, Chat.Server}, {:send_message, message, recipients}) do
      {:error, error_msg} ->
        :gen_tcp.send(client_socket, error_msg)

      {:ok, _, _recipients} ->
        :gen_tcp.send(client_socket, "")

      {:ok, _} ->
        :gen_tcp.send(client_socket, "")
    end
  end

  defp handle_nickname_command(client_socket, nickname) do
    case validate_nickname(nickname) do
      :ok ->
        case GenServer.call({:global, Chat.Server}, {:set_nickname, nickname}) do
          {:ok, success_msg} ->
            :gen_tcp.send(client_socket, success_msg)

          {:error, error_msg} ->
            :gen_tcp.send(client_socket, error_msg)
        end

      {:error, error_msg} ->
        :gen_tcp.send(client_socket, error_msg)
    end
  end

  defp handle_list_command(client_socket) do
    case GenServer.call({:global, Chat.Server}, :get_nicknames) do
      {:ok, registered_nicknames} ->
        registered_nicknames = Enum.join(registered_nicknames, ", ")
        message = "Registered users: #{registered_nicknames}\n"
        :gen_tcp.send(client_socket, message)
    end
  end

  defp handle_client_commands(sanitized_data, client_socket) do
    case String.split(sanitized_data, " ", parts: 3) do
      ["/LIST" | _rest] ->
        handle_list_command(client_socket)

      ["/NICK", nickname | _rest] ->
        handle_nickname_command(client_socket, nickname)

      ["/MSG", recipients_string, message | _rest] ->
        handle_message_command(client_socket, recipients_string, message)

      _ ->
        :gen_tcp.send(client_socket, "Invalid command\n")
    end
  end

  defp validate_nickname(nickname) do
    nickname_list = String.to_charlist(nickname)
    [first_char | remaining_chars] = nickname_list

    cond do
      length(nickname_list) > 10 ->
        {:error, "Error: nickname can only be up to 10 characters\n"}

      # First character must be a lowercase letter (97 - 122 is 'a' to 'z' as integer values)
      !(first_char in 65..90 or first_char in 97..122) ->
        {:error, "Error: nickname first character must be a letter\n"}

      # Check if remaining characters are valid
      Enum.any?(remaining_chars, fn char -> char not in @valid_nickname_characters end) ->
        {:error, "Error: nickname can only contain letters, numbers, or underscores\n"}

      # All validation checks have passed
      true ->
        :ok
    end
  end
end
