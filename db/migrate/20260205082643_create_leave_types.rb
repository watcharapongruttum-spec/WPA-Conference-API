class CreateLeaveTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :leave_types do |t|
      t.string :code      # SICK, PERSONAL
      t.string :name      # Sick Leave
      t.text   :description
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :leave_types, :code, unique: true
  end
end
