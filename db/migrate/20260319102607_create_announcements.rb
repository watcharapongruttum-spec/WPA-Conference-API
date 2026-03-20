class CreateAnnouncements < ActiveRecord::Migration[7.0]
  def change
    create_table :announcements do |t|
      t.text :message
      t.datetime :sent_at

      t.timestamps
    end
  end
end
