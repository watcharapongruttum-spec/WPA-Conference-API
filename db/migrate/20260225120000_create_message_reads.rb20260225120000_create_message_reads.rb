# db/migrate/20260225120000_create_message_reads.rb
class CreateMessageReads < ActiveRecord::Migration[7.0]
  def change
    create_table :message_reads do |t|
      t.references :chat_message, null: false, foreign_key: true
      t.references :delegate,     null: false, foreign_key: true
      t.datetime   :read_at,      null: false

      t.timestamps
    end

    # กัน duplicate — delegate อ่าน message เดียวกันได้แค่ 1 ครั้ง
    add_index :message_reads, [:chat_message_id, :delegate_id], unique: true

    # query "ใครอ่าง message X บ้าง" เร็วขึ้น
    add_index :message_reads, :read_at
  end
end