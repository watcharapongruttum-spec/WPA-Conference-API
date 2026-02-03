class AddChatRoomToChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_reference :chat_messages, :chat_room, foreign_key: true
  end
end
