class CreateChatRoomMembers < ActiveRecord::Migration[7.0]
  def change
    create_table :chat_room_members do |t|
      t.references :chat_room, null: false, foreign_key: true
      t.references :delegate, null: false, foreign_key: true
      t.timestamps
    end

    add_index :chat_room_members, %i[chat_room_id delegate_id], unique: true
  end
end
