class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  FCM_ALLOWED_TYPES = %w[new_message new_group_message admin_announce leave_reported].freeze

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
    msg = notification.notifiable

    sender_name = if msg.respond_to?(:sender)
                    msg&.sender&.name
                  elsif msg.respond_to?(:reported_by)
                    msg&.reported_by&.name
                  end || "Someone"

    title, body = build_title_body(notification, msg, sender_name)

    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM single notifiable_id=#{notification.notifiable_id}"

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: title,
      body:  body,
      data:  base_data(notification)
    )
  end

  def send_summary(notification, count, debug_id)
    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM summary count=#{count}"

    msg = notification.notifiable

    sender_name = if msg.respond_to?(:sender)
                    msg&.sender&.name
                  elsif msg.respond_to?(:reported_by)
                    msg&.reported_by&.name
                  end || "Someone"

    title = case notification.notification_type
            when "new_message"       then sender_name
            when "new_group_message" then msg&.chat_room&.title || "Group Chat"
            when "leave_reported"    then "แจ้งลาการนัดหมาย"
            else "New Messages"
            end

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: title,
      body:  "มี #{count} ข้อความที่ยังไม่ได้อ่าน",
      data:  base_data(notification)
    )
  end

  def build_title_body(notification, msg, sender_name)
    case notification.notification_type
    when "new_message"
      content = msg&.image? ? "📷 รูปภาพ" : msg&.content&.truncate(80)
      # ✅ title = ชื่อผู้ส่ง, body = เนื้อหาเลย (แบบ LINE/Messenger)
      [sender_name, content]
    when "new_group_message"
      room_title = msg&.chat_room&.title || "Group Chat"
      content    = msg&.image? ? "📷 รูปภาพ" : msg&.content&.truncate(80)
      # ✅ title = ชื่อ room, body = ชื่อผู้ส่ง: เนื้อหา
      [room_title, "#{sender_name}: #{content}"]
    when "leave_reported"
      ["แจ้งลาการนัดหมาย", "#{sender_name} ขอยกเลิกการนัดหมาย"]
    else
      ["Notification", msg&.content&.truncate(80).to_s]
    end
  end

  def base_data(notification)
    msg = notification.notifiable

    # ✅ ดึง sender_id และ chat_room_id เพื่อให้ Flutter navigate ได้ถูกหน้า
    sender_id    = msg&.sender_id if msg.respond_to?(:sender_id)
    chat_room_id = msg&.chat_room_id if msg.respond_to?(:chat_room_id)

    {
      type:            notification.notification_type,
      message_id:      notification.notifiable_id.to_s,
      notification_id: notification.id.to_s,
      screen:          "chat",
      sender_id:       sender_id.to_s,       # ✅ Flutter ใช้ไปหน้า direct chat
      chat_room_id:    chat_room_id.to_s     # ✅ Flutter ใช้ไปหน้า group chat
    }
  end
end