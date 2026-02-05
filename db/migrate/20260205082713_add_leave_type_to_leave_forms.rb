class AddLeaveTypeToLeaveForms < ActiveRecord::Migration[7.0]
  def change
    add_reference :leave_forms, :leave_type, foreign_key: true
  end
end
