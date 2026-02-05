class AddRoleToChatRoomMembers < ActiveRecord::Migration[7.0]
  def change
    add_column :room_members, :role, :integer
  end
end
