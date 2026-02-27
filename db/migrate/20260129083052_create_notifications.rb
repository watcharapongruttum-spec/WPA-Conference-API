class CreateNotifications < ActiveRecord::Migration[7.0]
  def change
    create_table :notifications do |t|
      t.references :delegate, null: false, foreign_key: true
      t.string :type, null: false
      t.references :notifiable, polymorphic: true, index: true
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, :read_at
  end
end
