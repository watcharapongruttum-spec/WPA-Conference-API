class CreateSecurityLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :security_logs do |t|
      t.references :delegate, null: false, foreign_key: true
      t.string :event
      t.string :ip

      t.timestamps
    end
  end
end
