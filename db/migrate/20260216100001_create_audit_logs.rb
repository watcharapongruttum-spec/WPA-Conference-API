class CreateAuditLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :audit_logs do |t|
      t.bigint :delegate_id, null: false
      t.string :action, null: false
      t.string :auditable_type, null: false
      t.bigint :auditable_id
      t.jsonb :changes
      t.string :ip_address
      t.string :user_agent
      t.datetime :created_at, null: false

      t.index %i[delegate_id created_at], name: 'idx_audit_logs_delegate_time'
      t.index %i[auditable_type auditable_id], name: 'idx_audit_logs_auditable'
      t.index [:action], name: 'idx_audit_logs_action'
    end

    add_foreign_key :audit_logs, :delegates
  end
end
