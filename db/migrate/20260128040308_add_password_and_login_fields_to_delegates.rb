class AddPasswordAndLoginFieldsToDelegates < ActiveRecord::Migration[7.0]
  def change
    add_column :delegates, :password_digest, :string
    add_column :delegates, :has_logged_in, :boolean, default: false
    add_column :delegates, :first_login_at, :datetime
    
    # ลบบรรทัดนี้ออกหรือเปลี่ยนเป็นดัชนีปกติ
    # add_index :delegates, :email, unique: true, name: 'index_delegates_on_email_unique', where: 'email IS NOT NULL'
    
    # ใช้ดัชนีปกติแทน (ไม่บังคับให้ไม่ซ้ำ)
    add_index :delegates, :email, name: 'index_delegates_on_email'
  end
end