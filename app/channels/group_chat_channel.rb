# app/channels/group_chat_channel.rb
class GroupChatChannel < ApplicationCable::Channel
  def subscribed
    @room = ChatRoom.find(params[:room_id])

    unless @room.chat_room_members.exists?(delegate_id: current_delegate.id)
      reject
      return
    end

    stream_for @room
    Chat::PresenceService.online(current_delegate.id)
    Rails.logger.info "✅ GroupChatChannel subscribed delegate=#{current_delegate.id} room=#{@room.id}"
  end

  def unsubscribed
    REDIS.del(room_active_key)
    Chat::PresenceService.offline(current_delegate.id)
    Rails.logger.info "👋 GroupChatChannel unsubscribed delegate=#{current_delegate.id}"
  end

  # ================= PING =================
  def ping(_data)
    Chat::PresenceService.refresh(current_delegate.id)
  end

  # ================= SEND TEXT =================
  def speak(data)
    data    = parse(data)
    content = data["content"].to_s.strip
    return if content.blank?

    msg = @room.chat_messages.create!(
      sender:       current_delegate,
      content:      content,
      message_type: "text"
    )

    MessageRead.mark_for(delegate: current_delegate, message_ids: [msg.id])
    Chat::Group::BroadcastService.message_sent(@room, msg)
    notify_group_members(msg)
  rescue ActiveRecord::RecordInvalid => e
    transmit(type: "error", message: e.message)
  rescue StandardError => e
    Rails.logger.error "[GroupChatChannel#speak] #{e.message}"
    transmit(type: "error", message: "Failed to send message")
  end

  # ================= SEND IMAGE =================
  def send_image(data)
    data     = parse(data)
    data_uri = data["image"]
    return transmit(type: "error", message: "No image provided") if data_uri.blank?

    msg = @room.chat_messages.create!(
      sender:       current_delegate,
      content:      "",
      message_type: "image"
    )

    Chat::ImageService.attach(message: msg, data_uri: data_uri)
    msg.reload
    MessageRead.mark_for(delegate: current_delegate, message_ids: [msg.id])
    Chat::Group::BroadcastService.message_sent(@room, msg)
    notify_group_members(msg)
  rescue ArgumentError => e
    msg&.destroy
    transmit(type: "error", message: e.message)
  rescue ActiveRecord::RecordInvalid => e
    transmit(type: "error", message: e.record.errors.full_messages.join(", "))
  end

  # ================= EDIT =================
  def edit_message(data)
    data = parse(data)
    msg  = find_own_message(data["message_id"])
    return transmit(type: "error", message: "Message not found") unless msg
    return transmit(type: "error", message: "Message deleted")   if msg.deleted?
    return transmit(type: "error", message: "Cannot edit image") if msg.image?

    msg.update!(content: data["content"].to_s.strip, edited_at: Time.current)
    Chat::Group::BroadcastService.message_edited(@room, msg)
  rescue ActiveRecord::RecordInvalid => e
    transmit(type: "error", message: e.message)
  end

  # ================= DELETE =================
  def delete_message(data)
    data = parse(data)
    msg  = find_own_message(data["message_id"])
    return transmit(type: "error", message: "Message not found") unless msg
    return transmit(type: "error", message: "Already deleted")   if msg.deleted?

    msg.update!(deleted_at: Time.current)
    Chat::Group::BroadcastService.message_deleted(@room, msg)
  end

  # ================= ENTER ROOM =================
  def enter_room(_data)
    REDIS.setex(room_active_key, 3600, "1")

    unread_ids = @room.chat_messages
                      .where.not(sender_id: current_delegate.id)
                      .where(deleted_at: nil)
                      .pluck(:id)
    return if unread_ids.empty?

    newly_read_ids = MessageRead.mark_for(
      delegate:    current_delegate,
      message_ids: unread_ids
    )
    return if newly_read_ids.empty?

    Chat::Group::BroadcastService.bulk_read(@room, current_delegate, newly_read_ids)
  end

  # ================= LEAVE ROOM =================
  def leave_room(_data)
    REDIS.del(room_active_key)
  end

  # ================= TYPING =================
  def typing(_data)
    Chat::Group::BroadcastService.typing(@room, current_delegate)
  end

  def stop_typing(_data)
    Chat::Group::BroadcastService.stop_typing(@room, current_delegate)
  end

  private

  def find_own_message(message_id)
    @room.chat_messages.find_by(id: message_id, sender_id: current_delegate.id)
  end

  def room_active_key
    "group_chat_open:#{@room.id}:#{current_delegate.id}"
  end

  def parse(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def notify_group_members(msg)
    recipient_ids = @room.chat_room_members
                         .where.not(delegate_id: current_delegate.id)
                         .pluck(:delegate_id)
    delegates = Delegate.where(id: recipient_ids).index_by(&:id)

    recipient_ids.each do |delegate_id|
      next if REDIS.get("group_chat_open:#{@room.id}:#{delegate_id}") == "1"

      delegate = delegates[delegate_id]
      next unless delegate

      notification = ::Notification.create!(
        delegate:          delegate,
        notification_type: "new_group_message",
        notifiable:        msg
      )

      Rails.cache.delete("dashboard:#{delegate_id}:v1")
      Notification::BroadcastService.call(notification)
    rescue StandardError => e
      Rails.logger.error "[GroupChatChannel] notify failed for delegate=#{delegate_id}: #{e.message}"
    end
  end
end