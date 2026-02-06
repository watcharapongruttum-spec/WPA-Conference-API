class AddTableAndDelegateToSchedules < ActiveRecord::Migration[7.0]
  def change
    add_reference :schedules, :table, foreign_key: true
    add_reference :schedules, :delegate, foreign_key: true
  end
end
