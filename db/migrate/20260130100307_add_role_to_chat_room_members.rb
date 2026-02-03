class AddRoleToChatRoomMembers < ActiveRecord::Migration[7.0]
  def change
    add_column :chat_room_members, :role, :integer
  end
end
