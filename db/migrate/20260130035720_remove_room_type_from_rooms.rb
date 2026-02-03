class RemoveRoomTypeFromRooms < ActiveRecord::Migration[7.0]
  def change
    remove_column :rooms, :room_type
  end
end
