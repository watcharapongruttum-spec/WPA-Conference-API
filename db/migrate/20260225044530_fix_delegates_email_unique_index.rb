class FixDelegatesEmailUniqueIndex < ActiveRecord::Migration[7.0]
  def up
    # ลบ index เก่าที่ไม่ unique ออกก่อน
    remove_index :delegates, name: 'index_delegates_on_email' if index_exists?(:delegates, :email, name: 'index_delegates_on_email')

    # ลบ index ที่ migration เก่าพยายามสร้างแต่ถูก skip ไป
    remove_index :delegates, name: 'idx_delegates_email_unique' if index_exists?(:delegates, :email, name: 'idx_delegates_email_unique')

    # สร้าง unique index ใหม่
    add_index :delegates, :email, unique: true, name: 'idx_delegates_email_unique'
  end

  def down
    remove_index :delegates, name: 'idx_delegates_email_unique'
    add_index :delegates, :email, name: 'index_delegates_on_email'
  end
end