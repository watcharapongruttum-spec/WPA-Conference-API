class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  FCM_ALLOWED_TYPES = %w[new_message new_group_message admin_announce].freeze

  BURST_WINDOW      = 60.seconds
  SUMMARY_THRESHOLD = 5

  def perform(notification_id)
    debug_id = SecureRandom.hex(4)
    Rails.logger.warn "🚀 [NDJ-#{debug_id}] START notification_id=#{notification_id}"

    notification = Notification.find_by(id: notification_id)
    unless notification
      Rails.logger.warn "❌ [NDJ-#{debug_id}] notification not found"
      return
    end

    Rails.logger.warn "📦 [NDJ-#{debug_id}] type=#{notification.notification_type} delegate_id=#{notification.delegate_id}"

    unless FCM_ALLOWED_TYPES.include?(notification.notification_type)
      Rails.logger.warn "⏭ [NDJ-#{debug_id}] skip type=#{notification.notification_type}"
      return
    end

    delegate = notification.delegate
    unless delegate&.device_token.present?
      Rails.logger.warn "⏭ [NDJ-#{debug_id}] no device token"
      return
    end

    Rails.logger.warn "📱 [NDJ-#{debug_id}] token=#{delegate.device_token.last(10)}"

    if Chat::PresenceService.online?(delegate.id)
      Rails.logger.warn "🟢 [NDJ-#{debug_id}] delegate online → skip FCM"
      return
    end

    recent = Notification.where(delegate: delegate)
                         .where(notification_type: notification.notification_type)
                         .where("created_at > ?", BURST_WINDOW.ago)

    count = recent.count

    Rails.logger.warn "📊 [NDJ-#{debug_id}] recent_count=#{count}"
    Rails.logger.warn "🧾 [NDJ-#{debug_id}] recent_ids=#{recent.pluck(:id)}"

    # ✅ FIX: เดิม count 2–5 จะ silent ทำให้ user พลาด notification
    # แก้เป็น: count == 1 → single, count >= 2 → summary เสมอ
    if count == 1
      Rails.logger.warn "📨 [NDJ-#{debug_id}] send_single"
      send_single(notification, debug_id)
    else
      Rails.logger.warn "📦 [NDJ-#{debug_id}] send_summary count=#{count}"
      send_summary(notification, count, debug_id)
    end
  rescue StandardError => e
    Rails.logger.error "💥 [NDJ-#{debug_id}] Failed: #{e.class} #{e.message}"
    Rails.logger.error e.backtrace.take(5).join("\n")
  end

  private

  def send_single(notification, debug_id)
    msg         = notification.notifiable
    sender_name = msg&.sender&.name || "Someone"

    # ✅ FIX: แยก title/body ตาม notification type
    title, body = build_title_body(notification, msg, sender_name)

    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM single message_id=#{notification.notifiable_id}"

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: title,
      body:  body,
      data:  base_data(notification)
    )
  end

  def send_summary(notification, count, debug_id)
    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM summary count=#{count}"

    # ✅ FIX: แยก title ตาม type
    title = case notification.notification_type
            when "new_group_message"
              notification.notifiable&.chat_room&.title || "Group Chat"
            else
              "New Messages"
            end

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: title,
      body:  "You have #{count} unread messages",
      data:  base_data(notification)
    )
  end

  # ✅ NEW: สร้าง title/body ให้เหมาะกับแต่ละ type
  def build_title_body(notification, msg, sender_name)
    case notification.notification_type
    when "new_group_message"
      room_title = msg&.chat_room&.title || "Group Chat"
      content    = msg&.image? ? "📷 รูปภาพ" : msg&.content&.truncate(80)
      [room_title, "#{sender_name}: #{content}"]
    when "new_message"
      content = msg&.image? ? "📷 รูปภาพ" : msg&.content&.truncate(80)
      ["New Message", "#{sender_name}: #{content}"]
    else
      ["Notification", msg&.content&.truncate(80).to_s]
    end
  end

  def base_data(notification)
    {
      type:            notification.notification_type,
      message_id:      notification.notifiable_id.to_s,
      notification_id: notification.id.to_s,
      screen:          "chat"
    }
  end
end