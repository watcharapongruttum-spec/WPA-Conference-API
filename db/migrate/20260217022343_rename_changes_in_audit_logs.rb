class RenameChangesInAuditLogs < ActiveRecord::Migration[7.0]
  def change
    return unless column_exists?(:audit_logs, :changes)

    rename_column :audit_logs, :changes, :record_changes
  end
end
