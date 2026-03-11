class AddPerUserDeleteToChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_messages, :deleted_for_sender_at,    :datetime
    add_column :chat_messages, :deleted_for_recipient_at, :datetime

    add_index :chat_messages, :deleted_for_sender_at
    add_index :chat_messages, :deleted_for_recipient_at
  end
end