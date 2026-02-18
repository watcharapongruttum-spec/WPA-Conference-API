class AddServiceNameToActiveStorageBlobs < ActiveRecord::Migration[7.0]
  def up
    add_column :active_storage_blobs, :service_name, :string

    # ใส่ค่า default ให้ blob เก่าทั้งหมด
    execute <<~SQL
      UPDATE active_storage_blobs
      SET service_name = 'local'
      WHERE service_name IS NULL
    SQL

    change_column_null :active_storage_blobs, :service_name, false
  end

  def down
    remove_column :active_storage_blobs, :service_name
  end
end
