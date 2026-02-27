class AuditLog < ApplicationRecord
  belongs_to :delegate, optional: true # ← แก้: optional เพื่อรองรับ login fail (delegate = nil)

  # ===== SCOPES =====
  scope :by_action,    ->(action)      { where(action: action) }
  scope :by_auditable, ->(type, id)    { where(auditable_type: type, auditable_id: id) }
  scope :recent,       ->(limit = 100) { order(created_at: :desc).limit(limit) }
  scope :by_delegate,  ->(delegate_id) { where(delegate_id: delegate_id) }

  # ===== ACTIONS =====
  ACTIONS = %w[
    login
    logout
    password_change
    password_reset_request
    password_reset_success
    password_reset_failed
    password_reset
    message_create
    message_update
    message_delete
    connection_request_create
    connection_request_accept
    connection_request_reject
    room_create
    room_delete
    room_join
    room_leave
    schedule_create
    schedule_update
    schedule_delete
    device_token_update
  ].freeze

  validates :action,         inclusion: { in: ACTIONS }
  validates :auditable_type, presence: true

  # ===== CLASS METHODS =====
  def self.log(delegate:, action:, auditable:, record_changes: {}, request: nil)
    # Guard: ถ้า action ไม่อยู่ใน ACTIONS อย่า crash — log warning แล้วออก
    unless ACTIONS.include?(action)
      Rails.logger.warn "[AuditLog] Unknown action '#{action}' — skipped"
      return
    end

    create!(
      delegate: delegate,
      action: action,
      auditable_type: auditable.class.name,
      auditable_id: auditable&.id,
      record_changes: record_changes,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  rescue StandardError => e
    Rails.logger.error "[AuditLog] Failed to log: #{e.message}"
  end

  def self.log_bulk(delegate:, action:, auditable_type:, request: nil)
    unless ACTIONS.include?(action)
      Rails.logger.warn "[AuditLog] Unknown action '#{action}' — skipped"
      return
    end

    create!(
      delegate: delegate,
      action: action,
      auditable_type: auditable_type,
      auditable_id: nil,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  rescue StandardError => e
    Rails.logger.error "[AuditLog] Failed to log bulk: #{e.message}"
  end
end
