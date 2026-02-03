class AddRoomToChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_reference :chat_messages, :room, foreign_key: true
  end
end
