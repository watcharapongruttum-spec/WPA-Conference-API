class CreateScheduleAttendances < ActiveRecord::Migration[7.0]
  def change
    create_table :schedule_attendances do |t|
      t.references :schedule, null: false, foreign_key: true
      t.string  :status          
      t.string  :reason         
      t.text    :explanation     
      t.references :reported_by, foreign_key: { to_table: :delegates }
      t.datetime :reported_at
      t.timestamps
    end

    add_index :schedule_attendances, :status
  end
end
