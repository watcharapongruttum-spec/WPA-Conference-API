class AddRoomKindToRooms < ActiveRecord::Migration[7.0]
  def change
    add_column :rooms, :room_kind, :integer
  end
end
