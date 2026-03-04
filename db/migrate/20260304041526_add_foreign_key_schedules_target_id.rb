class AddForeignKeySchedulesTargetId < ActiveRecord::Migration[7.0]
  def change
    add_foreign_key :schedules, :teams, column: :target_id, on_delete: :nullify
  end
end
