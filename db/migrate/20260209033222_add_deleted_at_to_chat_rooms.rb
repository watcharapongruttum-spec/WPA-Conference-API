class AddDeletedAtToChatRooms < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_rooms, :deleted_at, :datetime
    add_index  :chat_rooms, :deleted_at
  end
end
