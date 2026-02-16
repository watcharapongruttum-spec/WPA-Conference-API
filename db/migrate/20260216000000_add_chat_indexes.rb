class AddChatIndexes < ActiveRecord::Migration[7.0]
  def change
    add_index :chat_messages, :delivered_at
    add_index :chat_messages, [:recipient_id, :read_at],
              name: "idx_unread_messages"
  end
end
