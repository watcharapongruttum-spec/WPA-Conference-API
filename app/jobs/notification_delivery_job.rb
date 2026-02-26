class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    delegate = notification.delegate

    return unless delegate&.device_token.present?
    return if delegate.device_token.length < 20

    # ✅ เช็คอีกครั้งก่อนยิง — กัน race condition ตอน WS reconnect
    if Chat::PresenceService.online?(delegate.id)
      Rails.logger.info "[NotificationDeliveryJob] delegate=#{delegate.id} online → skip FCM"
      return
    end

    FcmService.send_push(
      token: delegate.device_token,
      title: notification_title(notification),
      body:  notification_body(notification),
      data: {
        type:            notification.notification_type,
        notification_id: notification.id.to_s,
        notifiable_type: notification.notifiable_type.to_s,
        notifiable_id:   notification.notifiable_id.to_s
      }
    )

  rescue => e
    Rails.logger.error "[NotificationDeliveryJob] Failed: #{e.message}"
  end

  private

  def notification_title(notification)
    case notification.notification_type
    when 'new_message'         then 'New Message'
    when 'connection_request'  then 'New Connection Request'
    when 'connection_accepted' then 'Connection Accepted'
    when 'connection_rejected' then 'Connection Declined'
    else 'New Notification'
    end
  end

  def notification_body(notification)
    case notification.notification_type
    when 'new_message'
      notification.notifiable&.content&.truncate(100) || 'You have a new message'
    when 'connection_request'
      "#{notification.notifiable&.requester&.name} wants to connect"
    when 'connection_accepted'
      "#{notification.notifiable&.target&.name} accepted your connection"
    when 'connection_rejected'
      "#{notification.notifiable&.target&.name} declined your request"
    else 'You have a new notification'
    end
  end
end