class AddDeviceTokenToDelegates < ActiveRecord::Migration[7.0]
  def change
    add_column :delegates, :device_token, :string
  end
end
