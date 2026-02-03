# db/migrate/XXXXXX_create_messages.rb
class CreateMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :messages do |t|
      t.bigint :sender_id, null: false
      t.bigint :recipient_id, null: false
      t.text :content, null: false
      t.datetime :read_at
      t.timestamps
    end
    
    # เพิ่ม foreign keys
    add_foreign_key :messages, :delegates, column: :sender_id
    add_foreign_key :messages, :delegates, column: :recipient_id
    
    # เพิ่มดัชนี
    add_index :messages, [:sender_id, :recipient_id]
    add_index :messages, :created_at
  end
end