class MakeAuditLogDelegateNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null :audit_logs, :delegate_id, true
  end
end