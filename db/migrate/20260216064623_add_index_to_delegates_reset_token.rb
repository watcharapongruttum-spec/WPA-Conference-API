class AddIndexToDelegatesResetToken < ActiveRecord::Migration[7.0]
  def change
    add_index :delegates, :reset_password_token, unique: true
  end
end
