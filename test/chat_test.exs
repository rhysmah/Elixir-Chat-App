defmodule ChatTest do
  use ExUnit.Case
  doctest Chat.Server

  describe "Chat.Server functionality" do
    setup do
      {:ok, server} = Chat.Server.start_link()
      {:ok, server: server}
    end

    test "registers a new nickname successfully", %{server: server} do
      assert {:ok, :nickname_registered} = Chat.Server.set_nickname("johndoe")
      assert {:ok, nicknames} = Chat.Server.get_nicknames()
      assert "johndoe" in nicknames
    end

    test "prevents duplicate nicknames from being registered", %{server: server} do
      Chat.Server.set_nickname("johndoe")
      assert {:error, :nickname_already_registered} = Chat.Server.set_nickname("johndoe")
    end

    test "retrieves list of registered nicknames", %{server: server} do
      Chat.Server.set_nickname("johndoe")
      Chat.Server.set_nickname("janedoe")
      assert {:ok, nicknames} = Chat.Server.get_nicknames()
      assert length(nicknames) == 2
      assert "johndoe" in nicknames
      assert "janedoe" in nicknames
    end

    # Add more tests for send_msg_to_users and other functionalities
  end
end
