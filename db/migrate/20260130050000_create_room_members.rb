class CreateRoomMembers < ActiveRecord::Migration[7.0]
  def change
    create_table :room_members do |t|
      # migration แก้
      t.references :chat_room, null: false, foreign_key: true

      t.references :delegate, null: false, foreign_key: true

      t.timestamps
    end
  end
end
