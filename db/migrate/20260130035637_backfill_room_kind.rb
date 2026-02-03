class BackfillRoomKind < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      UPDATE rooms
      SET room_kind =
        CASE room_type
          WHEN 'direct' THEN 0
          WHEN 'group'  THEN 1
          WHEN 'event'  THEN 2
          ELSE 0
        END
    SQL
  end

  def down
    # ไม่ rollback (ปลอดภัยกว่า)
  end
end
