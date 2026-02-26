class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  FCM_ALLOWED_TYPES = %w[new_message admin_announce].freeze

  BURST_WINDOW = 60.seconds
  SUMMARY_THRESHOLD = 5

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

    # ✅ ถ้าออนไลน์ → ไม่ส่ง
    if Chat::PresenceService.online?(delegate.id)
      Rails.logger.info "[NotificationDeliveryJob] delegate=#{delegate.id} online → skip FCM"
      return
    end

    # ✅ ดึง notification ล่าสุดใน burst window
    recent = Notification.where(delegate: delegate)
                         .where(notification_type: notification.notification_type)
                         .where("created_at > ?", BURST_WINDOW.ago)

    count = recent.count

    Rails.logger.info "[NotificationDeliveryJob] recent_count=#{count}"

    if count == 1
      send_single(notification)

    elsif count <= SUMMARY_THRESHOLD
      Rails.logger.info "[NotificationDeliveryJob] burst suppressed"
      return

    else
      send_summary(notification, count)
    end

  rescue => e
    Rails.logger.error "[NotificationDeliveryJob] Failed: #{e.message}"
  end

  private

  # -------------------------
  # ส่งข้อความเดี่ยว
  # -------------------------
  def send_single(notification)
    msg = notification.notifiable
    sender_name = msg&.sender&.name || "Someone"

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: "New Message",
      body: "#{sender_name}: #{msg&.content&.truncate(80)}",
      data: base_data(notification)
    )
  end

  # -------------------------
  # ส่ง summary
  # -------------------------
  def send_summary(notification, count)
    FcmService.send_push(
      token: notification.delegate.device_token,
      title: "You have #{count} new messages",
      body: "+#{count} new messages",
      data: base_data(notification)
    )
  end

  # -------------------------
  # Data payload
  # -------------------------
  def base_data(notification)
    {
      type: notification.notification_type,
      message_id: notification.notifiable_id.to_s,
      notification_id: notification.id.to_s,
      screen: "chat"
    }
  end
end