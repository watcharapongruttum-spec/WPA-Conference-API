class AddDeliveredAtToChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_messages, :delivered_at, :datetime
  end
end
