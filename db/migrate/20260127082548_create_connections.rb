# db/migrate/XXXXXX_create_connections.rb
class CreateConnections < ActiveRecord::Migration[7.0]
  def change
    create_table :connections do |t|
      t.bigint :requester_id, null: false
      t.bigint :target_id, null: false
      t.string :status, default: 'pending', null: false
      t.timestamps
    end

    # เพิ่ม foreign keys
    add_foreign_key :connections, :delegates, column: :requester_id
    add_foreign_key :connections, :delegates, column: :target_id

    # เพิ่มดัชนี
    add_index :connections, %i[requester_id target_id], unique: true
    add_index :connections, :status
  end
end
