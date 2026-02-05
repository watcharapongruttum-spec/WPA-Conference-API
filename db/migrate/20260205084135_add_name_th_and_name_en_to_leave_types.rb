class AddNameThAndNameEnToLeaveTypes < ActiveRecord::Migration[7.0]
  def change
    add_column :leave_types, :name_th, :string
    add_column :leave_types, :name_en, :string
  end
end
