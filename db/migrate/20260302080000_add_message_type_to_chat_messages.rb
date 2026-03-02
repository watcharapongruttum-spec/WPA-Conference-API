class AddMessageTypeToChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_messages, :message_type, :string, default: "text", null: false
  end
end