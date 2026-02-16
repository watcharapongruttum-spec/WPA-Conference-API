class AddResetPasswordToDelegates < ActiveRecord::Migration[7.0]
  def change
    add_column :delegates, :reset_password_token, :string
    add_column :delegates, :reset_password_sent_at, :datetime
  end
end
