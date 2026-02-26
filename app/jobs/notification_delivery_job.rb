class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  # ส่ง FCM เฉพาะประเภทที่กำหนด
  FCM_ALLOWED_TYPES = %w[new_message new_group_message admin_announce].freeze

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    unless FCM_ALLOWED_TYPES.include?(notification.notification_type)
      Rails.logger.info "[NotificationDeliveryJob] skip type=#{notification.notification_type}"
      return
    end

    delegate = notification.delegate
    return unless delegate&.device_token.present?
    return if delegate.device_token.length < 20

    # ✅ ถ้าออนไลน์ → ไม่ส่ง FCM (เหมือน Facebook)
    if Chat::PresenceService.online?(delegate.id)
      Rails.logger.info "[NotificationDeliveryJob] delegate=#{delegate.id} online → skip FCM"
      return
    end

    # ✅ กัน spam: ถ้ามีแจ้งเตือนประเภทเดียวกันใน 5 วิล่าสุด → ไม่ส่ง
    if recent_duplicate?(delegate, notification)
      Rails.logger.info "[NotificationDeliveryJob] duplicate suppressed"
      return
    end

    # ✅ รวมจำนวนข้อความล่าสุด (เหมือน Facebook)
    recent_count = recent_count(delegate, notification)

    FcmService.send_push(
      token: delegate.device_token,
      title: notification_title(notification, recent_count),
      body:  notification_body(notification, recent_count),
      data: {
        type: notification.notification_type,
        chat_id: notification.notifiable_id.to_s,
        notification_id: notification.id.to_s,
        screen: "chat" # มือถือใช้เปิดหน้า
      }
    )
  rescue => e
    Rails.logger.error "[NotificationDeliveryJob] Failed: #{e.message}"
  end

  private

  # -------------------------
  # Helpers
  # -------------------------

  def recent_duplicate?(delegate, notification)
    Notification.where(delegate: delegate)
                .where(notification_type: notification.notification_type)
                .where("created_at > ?", 5.seconds.ago)
                .exists?
  end

  def recent_count(delegate, notification)
    Notification.where(delegate: delegate)
                .where(notification_type: notification.notification_type)
                .where("created_at > ?", 1.minute.ago)
                .count
  end

  # -------------------------
  # Title
  # -------------------------

  def notification_title(notification, count)
    case notification.notification_type
    when 'new_message'
      count > 1 ? "You have #{count} new messages" : "New Message"

    when 'new_group_message'
      room_name = notification.notifiable&.chat_room&.title || "Group"
      count > 1 ? "#{room_name} (#{count} new)" : room_name

    when 'admin_announce'
      "📢 Announcement"
    end
  end

  # -------------------------
  # Body
  # -------------------------

  def notification_body(notification, count)
    return "+#{count} new messages" if count > 1

    case notification.notification_type
    when 'new_message', 'new_group_message'
      msg = notification.notifiable
      "#{msg&.sender&.name}: #{msg&.content&.truncate(80)}"

    when 'admin_announce'
      notification.notifiable&.content&.truncate(100) || 'New announcement'
    end
  end
end