class AddNotNullToRoomKind < ActiveRecord::Migration[7.0]
  def change
    change_column_null :rooms, :room_kind, false
  end
end
