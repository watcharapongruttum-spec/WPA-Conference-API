class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  # ✅ FCM เฉพาะ 2 ประเภทเท่านั้น
  FCM_ALLOWED_TYPES = %w[new_message new_group_message admin_announce].freeze

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    # ✅ ไม่ใช่ประเภทที่อนุญาต → skip ทันที
    unless FCM_ALLOWED_TYPES.include?(notification.notification_type)
      Rails.logger.info "[NotificationDeliveryJob] skip — type=#{notification.notification_type} not in FCM_ALLOWED_TYPES"
      return
    end

    delegate = notification.delegate
    return unless delegate&.device_token.present?
    return if delegate.device_token.length < 20

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
    when 'new_message'       then 'New Message'
    when 'new_group_message'
      # ✅ ใช้ชื่อห้องเป็น title
      notification.notifiable&.chat_room&.title || 'New Group Message'
    when 'admin_announce'    then 'Announcement'
    end
  end

  def notification_body(notification)
    case notification.notification_type
    when 'new_message'
      msg = notification.notifiable
      "#{msg&.sender&.name}: #{msg&.content&.truncate(100)}"
    when 'new_group_message'
      msg = notification.notifiable
      "#{msg&.sender&.name}: #{msg&.content&.truncate(100)}"
    when 'admin_announce'
      notification.notifiable&.content&.truncate(100) || 'New announcement'
    end
  end
end