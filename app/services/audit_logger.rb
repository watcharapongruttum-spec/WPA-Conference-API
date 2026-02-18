module AuditLogger

    # ================= AUTH =================

  def self.login(delegate: nil, request: nil, email: nil, metadata: nil, success: true)
    AuditLog.log(
      delegate: delegate,
      action: 'login',
      auditable: delegate,
      record_changes: {
        success: success,
        email: email || delegate&.email,
        ip: metadata&.dig(:ip) || request&.remote_ip,
        user_agent: metadata&.dig(:user_agent)
      },
      request: request
    )
  rescue => e
    Rails.logger.error("[AuditLogger] login failed: #{e.message}")
  end

  def self.logout(delegate:, request:)
    AuditLog.log(
      delegate: delegate,
      action: 'logout',
      auditable: delegate,
      record_changes: { ip: request.remote_ip },
      request: request
    )
  end

  def self.password_change(delegate:, request:, success: true)
    AuditLog.log(
      delegate: delegate,
      action: 'password_change',
      auditable: delegate,
      record_changes: {
        success: success,
        changed_at: Time.current
      },
      request: request
    )
  rescue => e
    Rails.logger.error("[AuditLogger] password_change failed: #{e.message}")
  end

  def self.password_reset_request(delegate:, request:)
    AuditLog.log(
      delegate: delegate,
      action: 'password_reset_request',
      auditable: delegate,
      record_changes: {
        ip: request.remote_ip,
        requested_at: Time.current
      },
      request: request
    )
  rescue => e
    Rails.logger.error("[AuditLogger] password_reset_request failed: #{e.message}")
  end

  def self.password_reset(delegate:, request:, success:)
    AuditLog.log(
      delegate: delegate,
      action: success ? 'password_reset_success' : 'password_reset_failed',
      auditable: delegate,
      record_changes: {
        ip: request.remote_ip
      },
      request: request
    )
  rescue => e
    Rails.logger.error("[AuditLogger] password_reset failed: #{e.message}")
  end

  # ================= OTHER SECTIONS (เหมือนเดิมได้) =================

  










  # ===== MESSAGES =====
  def self.message_created(message, request)
    AuditLog.log(
      delegate: message.sender,
      action: 'message_create',
      auditable: message,
      record_changes: { 
        content_length: message.content&.length,
        recipient_id: message.recipient_id,
        chat_room_id: message.chat_room_id
      },
      request: request
    )
  end
  
  def self.message_deleted(message, request)
    AuditLog.log(
      delegate: message.sender,
      action: 'message_delete',
      auditable: message,
      record_changes: { deleted_at: Time.current, message_id: message.id },
      request: request
    )
  end
  
  def self.message_updated(message, record_changes, request)
    AuditLog.log(
      delegate: message.sender,
      action: 'message_update',
      auditable: message,
      record_changes: record_changes,
      request: request
    )
  end
  
  # ===== CONNECTIONS =====
  def self.connection_request_created(request_obj, http_request)
    AuditLog.log(
      delegate: request_obj.requester,
      action: 'connection_request_create',
      auditable: request_obj,
      record_changes: { target_id: request_obj.target_id },
      request: http_request
    )
  end
  
  def self.connection_accepted(request_obj, http_request)
    AuditLog.log(
      delegate: request_obj.target,
      action: 'connection_request_accept',
      auditable: request_obj,
      record_changes: { status: 'accepted', requester_id: request_obj.requester_id },
      request: http_request
    )
  end
  
  def self.connection_rejected(request_obj, http_request)
    AuditLog.log(
      delegate: request_obj.target,
      action: 'connection_request_reject',
      auditable: request_obj,
      record_changes: { status: 'rejected', requester_id: request_obj.requester_id },
      request: http_request
    )
  end
  
  # ===== ROOMS =====
  def self.room_created(room, delegate, http_request)
    AuditLog.log(
      delegate: delegate,
      action: 'room_create',
      auditable: room,
      record_changes: { title: room.title, room_kind: room.room_kind },
      request: http_request
    )
  end
  
  def self.room_deleted(room, delegate, http_request)
    AuditLog.log(
      delegate: delegate,
      action: 'room_delete',
      auditable: room,
      record_changes: { deleted_at: Time.current },
      request: http_request
    )
  end
  
  def self.room_joined(room, delegate, http_request)
    AuditLog.log(
      delegate: delegate,
      action: 'room_join',
      auditable: room,
      record_changes: { room_id: room.id },
      request: http_request
    )
  end
  
  def self.room_left(room, delegate, http_request)
    AuditLog.log(
      delegate: delegate,
      action: 'room_leave',
      auditable: room,
      record_changes: { room_id: room.id },
      request: http_request
    )
  end
  
  # ===== DEVICE =====
  def self.device_token_updated(delegate, request)
    AuditLog.log(
      delegate: delegate,
      action: 'device_token_update',
      auditable: delegate,
      record_changes: { has_token: delegate.device_token.present? },
      request: request
    )
  end
end