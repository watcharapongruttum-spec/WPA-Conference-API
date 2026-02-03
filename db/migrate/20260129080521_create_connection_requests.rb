class CreateConnectionRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :connection_requests do |t|
      t.bigint :requester_id, null: false
      t.bigint :target_id, null: false
      t.string :status, default: 'pending', null: false
      t.datetime :accepted_at
      
      t.timestamps
    end
    
    # เพิ่มดัชนีสำหรับการค้นหา
    add_index :connection_requests, :requester_id
    add_index :connection_requests, :target_id
    add_index :connection_requests, :status
    add_index :connection_requests, [:requester_id, :target_id], unique: true, name: 'index_connection_requests_on_pair'
    
    # เพิ่มข้อจำกัด (foreign keys) ไปยังตาราง delegates
    add_foreign_key :connection_requests, :delegates, column: :requester_id
    add_foreign_key :connection_requests, :delegates, column: :target_id
  end
end