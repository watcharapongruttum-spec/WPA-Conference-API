# app/channels/chat_room_channel.rb
class ChatRoomChannel < ApplicationCable::Channel
  def subscribed
    @room = ChatRoom.find(params[:room_id])

    unless @room.delegates.include?(current_delegate)
      reject
      return
    end

    stream_for @room
    Chat::PresenceService.online(current_delegate.id)
  end

  def unsubscribed
    Chat::PresenceService.offline(current_delegate.id)
  end

  # ================= PING =================
  def ping(_data)
    Chat::PresenceService.refresh(current_delegate.id)
  end

  # ================= SEND TEXT =================
  def send_message(data)
    data    = parse(data)
    content = data["content"].to_s.strip
    return if content.blank?

    msg = @room.chat_messages.create!(
      sender:       current_delegate,
      content:      content,
      message_type: "text"  # ✅
    )

    broadcast_message(msg)
    auto_read_if_open(msg)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "[ChatRoomChannel] create! failed: #{e.message}"
    transmit(type: "error", message: e.record.errors.full_messages.join(", "))
  end

  # ================= SEND IMAGE ✅ =================
  def send_image(data)
    data     = parse(data)
    data_uri = data["image"]
    return transmit(type: "error", message: "No image provided") if data_uri.blank?

    msg = @room.chat_messages.create!(
      sender:       current_delegate,
      content:      "",
      message_type: "image"  # ✅
    )

    Chat::ImageService.attach(message: msg, data_uri: data_uri)
    broadcast_message(msg)
    auto_read_if_open(msg)
  rescue ArgumentError => e
    msg&.destroy
    transmit(type: "error", message: e.message)
  rescue ActiveRecord::RecordInvalid => e
    transmit(type: "error", message: e.record.errors.full_messages.join(", "))
  end

  # ================= ENTER ROOM =================
  def enter_room(_data)
    other = other_user
    return unless other

    redis.set(presence_key(current_delegate.id, other.id), 1)
    mark_conversation_as_read(other.id)
  end

  # ================= LEAVE ROOM =================
  def leave_room(_data)
    other = other_user
    return unless other

    redis.del(presence_key(current_delegate.id, other.id))
  end

  # ================= EDIT =================
  def edit_message(data)
    data = parse(data)
    msg  = @room.chat_messages.find_by(id: data["message_id"])
    return unless msg && msg.sender == current_delegate
    return transmit(type: "error", message: "Cannot edit image") if msg.image?  # ✅

    msg.update!(content: data["content"], edited_at: Time.current)

    ChatRoomChannel.broadcast_to(@room, {
      type:       "room_message_updated",
      message_id: msg.id,
      content:    msg.content
    })
  end

  # ================= DELETE =================
  def delete_message(data)
    data = parse(data)
    msg  = @room.chat_messages.find_by(id: data["message_id"])
    return unless msg && msg.sender == current_delegate

    msg.update!(deleted_at: Time.current)

    ChatRoomChannel.broadcast_to(@room, {
      type:       "room_message_deleted",
      message_id: msg.id
    })
  end

  private

  def broadcast_message(msg)
    ChatRoomChannel.broadcast_to(@room, {
      type:    "room_message",
      room_id: @room.id,
      message: {
        id:           msg.id,
        content:      msg.content,
        message_type: msg.message_type,  # ✅
        image_url:    msg.image_url,     # ✅
        created_at:   TimeFormatter.format(msg.created_at),
        sender:       DelegatePresenter.minimal(current_delegate)
      }
    })
  end

  def parse(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def redis
    REDIS
  end

  def other_user
    @room.delegates.where.not(id: current_delegate.id).first
  end

  def presence_key(viewer_id, target_id)
    "chat_open:#{viewer_id}:#{target_id}"
  end

  def other_user_open?
    other = other_user
    return false unless other
    redis.get(presence_key(other.id, current_delegate.id)) == "1"
  end

  def auto_read_if_open(msg)
    return unless other_user_open?

    msg.update!(read_at: Time.current)

    ChatRoomChannel.broadcast_to(@room, {
      type:       "message_read",
      message_id: msg.id,
      read_at:    TimeFormatter.format(msg.read_at)
    })
  end

  def mark_conversation_as_read(target_id)
    now   = Time.current
    scope = ChatMessage.where(
      sender_id:    target_id,
      recipient_id: current_delegate.id,
      read_at:      nil,
      deleted_at:   nil
    )

    ids = scope.pluck(:id)
    return if ids.empty?

    ChatMessage.where(id: ids).update_all(read_at: now)

    ChatRoomChannel.broadcast_to(@room, {
      type:        "bulk_read",
      message_ids: ids,
      read_at:     TimeFormatter.format(now)
    })
  end
end