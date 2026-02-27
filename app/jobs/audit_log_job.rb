class AuditLogJob < ApplicationJob
  queue_as :default

  def perform(delegate_id:, action:, auditable_type:, auditable_id:, changes:, ip:, user_agent:)
    delegate = Delegate.find_by(id: delegate_id)
    return unless delegate

    AuditLog.create!(
      delegate: delegate,
      action: action,
      auditable_type: auditable_type,
      auditable_id: auditable_id,
      changes: changes,
      ip_address: ip,
      user_agent: user_agent
    )
  rescue StandardError => e
    Rails.logger.error "[AuditLogJob] Failed: #{e.message}"
  end
end
