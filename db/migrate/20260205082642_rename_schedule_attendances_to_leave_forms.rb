class RenameScheduleAttendancesToLeaveForms < ActiveRecord::Migration[7.0]
  def change
    rename_table :schedule_attendances, :leave_forms
  end
end
