class AllowNullDelegateInSecurityLogs < ActiveRecord::Migration[7.0]
  def change
    change_column_null :security_logs, :delegate_id, true
  end
end
