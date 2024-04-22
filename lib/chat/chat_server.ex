defmodule Chat.Server do
  @moduledoc """
  A chat server module for managing user nicknames and messaging.

  This module implements a chat server that allows users to register unique nicknames,
  retrieve a list of currently registered nicknames, and send messages to individual users
  or broadcast messages to all users using a GenServer.
  """

  use GenServer

  @name {:global, __MODULE__}
  @stateless :no_state

  ####################
  # PUBLIC INTERFACE #
  ####################

  @doc """
  Starts the chat server as a globally registered GenServer instance.

  ## Return Values
  - `{:ok, pid}`: PID of the started GenServer on success.
  - An error tuple if the server could not be started.

  ## Examples
    iex> Chat.Server.start_link()
    "Chat.Server {:global, Chat.Server} has started."
    {:ok, #PID<0.123.0>}
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, @stateless, name: @name)
  end

  @doc """
  Registers a new nickname for the user with the server. This process involves validating
  the nickname and ensuring it is not already registered. Nicknames are stored in an ETS table
  for persistent, cross-process access.

  ## Parameters
  - `requested_nickname`: The nickname the user wishes to register.

  ## Return Values
  - `{:ok, :nickname_registered}`: On successful registration.
  - `{:error, :nickname_already_registered}` or `{:error, reason}`: If the registration
  fails due to the nickname being taken or failing validation.

  ## Examples
      iex> Chat.Server.set_nickname("johndoe")
      {:ok, :nickname_registered}
  """
  def set_nickname(requested_nickname) do
    GenServer.call(@name, {:set_nickname, requested_nickname})
  end

  @doc """
  Retrieves a list of currently registered nicknames from the server. The nicknames are
  read from an ETS table, reflecting the current state of registered users.

  ## Return Values
  - `{:ok, nicknames}`: A list of currently registered nicknames.

  ## Examples
      iex> Chat.Server.get_nicknames()
      {:ok, ["johndoe", "janedoe"]}
  """
  def get_nicknames do
    GenServer.call(@name, :get_nicknames)
  end

  @doc """
  Sends a message to specified recipients or broadcasts to all users. Individual
  users or groups are identified by their nicknames, with "*" denoting a broadcast
  to all registered users.

  ## Parameters
  - `message`: The message to be sent.
  - `recipients`: A list of nicknames to send the message to, or ["*"] for a broadcast.

  ## Return Values
  - `:ok`: On successful message delivery.
  - `{:error, :unregistered_user}`: If the sender is not registered.
  - `{:error, reason}`: For other errors during message delivery.

  ## Examples
      iex> Chat.Server.send_msg_to_users("Hello, World!", ["johndoe"])
      :ok
  """
  def send_msg_to_users(message, recipients) do
    GenServer.call(@name, {:send_message, message, recipients})
  end

  @doc """
  Removes a nickname from the registered users.

  ## Parameters
  - `user_pid`: The PID to remove.

  ## Return Values
  - `:ok`: On successful removal.
  - `{:error, :user_not_found}`: If the nickname was not registered.

  ## Examples
      iex> Chat.Server.remove_user("testuser")
      :ok
  """
  def remove_user(user_pid) do
    GenServer.call(@name, {:remove_user, user_pid})
  end

  ##################
  # IMPLEMENTATION #
  ##################

  @impl true
  def init(_args) do
    # Initializes the Chat.Server with no state;
    # it uses an ETS table for state management.
    {:ok, @stateless}
  end

  @impl true
  def handle_call({:set_nickname, requested_nickname}, {pid, _} = _request_proxy_pid, @stateless) do
    # Pulls all nicknames from ETS table, then checks if
    # requested nickname matches any registered nicknames.
    is_nickname_taken =
      :ets.match_object(:users, {:_, requested_nickname}) |> Enum.any?()

    case is_nickname_taken do
      # If nickname already registered, return error.
      true ->
        {:reply, {:error, "Nickname '#{requested_nickname}' is already taken\n"}, @stateless}

      # If nickname not registered, check if user already has a registered nickname
      false ->
        old_nickname_entry = :ets.lookup(:users, pid)

        case old_nickname_entry do
          # No matches; new user is registering a nickname
          [] ->
            :ets.insert(:users, {pid, requested_nickname})
            IO.puts("#{requested_nickname} has registered as a new user")

            {:reply, {:ok, "Nickname registered as '#{requested_nickname}'\n"}, @stateless}

          # Match; the user is updating their nickname
          [{_old_pid, old_nickname}] ->
            :ets.delete(:users, old_nickname)
            :ets.insert(:users, {pid, requested_nickname})
            IO.puts("#{old_nickname} changed their nickname to #{requested_nickname}")

            {:reply,
             {:ok, "Nickname changed from '#{old_nickname}' to '#{requested_nickname}'\n"},
             @stateless}
        end
    end
  end

  @impl true
  def handle_call(:get_nicknames, _request_proxy_pid, @stateless) do
    registered_nicknames =
      :ets.tab2list(:users)
      |> Enum.map(fn {_, nickname} ->
        nickname
      end)

    {:reply, {:ok, registered_nicknames}, @stateless}
  end

  @impl true
  def handle_call(
        {:send_message, message, recipients},
        {sender_pid, _} = _request_proxy_pid,
        @stateless
      ) do
    case get_sender_nickname(sender_pid) do
      nil ->
        {:reply, {:error, "Error: You must register before sending messages\n"}, @stateless}

      sender_nickname ->
        handle_send_messages(sender_nickname, message, recipients, sender_pid)
    end
  end

  @impl true
  def handle_call({:remove_user, user_pid}, _from, @stateless) do
    case :ets.lookup(:users, user_pid) do
      [{user_pid, nickname}] ->
        :ets.delete(:users, user_pid)
        IO.puts("#{nickname} has left the chat")
        {:reply, :ok, @stateless}

      [] ->
        {:reply, {:error, "Nickname not registered"}, @stateless}
    end
  end

  ####################
  # HELPER FUNCTIONS #
  ####################

  defp get_sender_nickname(sender_pid) do
    :ets.lookup(:users, sender_pid)
    |> case do
      [] -> nil
      [nickname] -> nickname
    end
  end

  defp handle_send_messages(sender_nickname, message, receipients, pid) do
    case receipients do
      ["*"] -> send_message_to_all(message, sender_nickname, pid)
      _ -> send_message_to_individuals(message, sender_nickname, receipients)
    end
  end

  defp send_message_to_all(message, sender_nickname, sender_pid) do
    :ets.tab2list(:users)
    |> Enum.each(fn {recipient_pid, _} ->
      if recipient_pid != sender_pid do
        send(recipient_pid, {:message, sender_nickname, message})
      end
    end)

    IO.puts("#{inspect(sender_nickname)} sent a message to all registered users")
    {:reply, {:ok, :messages_sent}, @stateless}
  end

  defp send_message_to_individuals(message, sender_nickname, recipients) do
    :ets.tab2list(:users)
    |> Enum.each(fn {pid, nickname} ->
      if Enum.member?(recipients, nickname) do
        send(pid, {:message, sender_nickname, message})

        IO.puts("#{inspect(sender_nickname)} sent a message to #{inspect(nickname)}")
      end
    end)

    {:reply, {:ok, :messages_sent, recipients}, @stateless}
  end
end
