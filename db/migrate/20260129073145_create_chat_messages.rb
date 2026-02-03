class CreateChatMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :chat_messages do |t|
      t.bigint :sender_id, null: false
      t.bigint :recipient_id, null: false
      t.text :content, null: false
      t.datetime :read_at
      
      t.timestamps
    end
    
    # เพิ่มดัชนีสำหรับการค้นหา
    add_index :chat_messages, :sender_id
    add_index :chat_messages, :recipient_id
    add_index :chat_messages, [:sender_id, :recipient_id]
    add_index :chat_messages, :read_at
    
    # เพิ่มข้อจำกัด (foreign keys) ไปยังตาราง delegates
    add_foreign_key :chat_messages, :delegates, column: :sender_id
    add_foreign_key :chat_messages, :delegates, column: :recipient_id
  end
end