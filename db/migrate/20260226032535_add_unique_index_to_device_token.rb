# migration ใหม่
class AddUniqueIndexToDeviceToken < ActiveRecord::Migration[7.0]
  def change
    # ลบ index เก่าก่อน
    remove_index :delegates, name: 'idx_delegates_device_token', if_exists: true

    # เพิ่ม unique index (allow nil เพราะหลายคนไม่มี token)
    add_index :delegates, :device_token,
              unique: true,
              where: 'device_token IS NOT NULL',
              name: 'idx_delegates_device_token_unique'
  end
end
