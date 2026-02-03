class MakeRecipientNullableInChatMessages < ActiveRecord::Migration[7.0]
  def change
    change_column_null :chat_messages, :recipient_id, true
  end
end
