class AddEditAndDeleteToChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_messages, :edited_at, :datetime
    add_column :chat_messages, :deleted_at, :datetime
  end
end
