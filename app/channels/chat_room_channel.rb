class ChatRoomChannel < ApplicationCable::Channel
  def subscribed
    @room = ChatRoom.find(params[:room_id])
    reject unless @room.delegates.include?(current_delegate)

    stream_for @room
  end


  def self.auto_read_if_open(sender:, recipient:, message:)
    key = "chat_open:#{recipient.id}:#{sender.id}"
    return unless Redis.current.get(key) == "1"

    message.update!(read_at: Time.current)

    broadcast_to(sender, {
      type: "message_read",
      message_id: message.id,
      read_at: message.read_at
    })

    broadcast_to(recipient, {
      type: "message_read",
      message_id: message.id,
      read_at: message.read_at
    })
  end



  # ================= SEND =================
  def send_message(data)
    data = parse(data)

    msg = @room.chat_messages.create!(
      sender: current_delegate,
      content: data["content"]
    )

    # broadcast message
    ChatRoomChannel.broadcast_to(@room, {
      type: "room_message",
      room_id: @room.id,
      message: serializer(msg)
    })

    # ===== AUTO READ IF OTHER USER OPEN ROOM =====
    auto_read_if_open(msg)
  end

  # ================= ENTER ROOM =================
  def enter_room(_data)
    other = other_user
    return unless other

    # set presence
    redis.set(presence_key(current_delegate.id, other.id), 1)

    mark_conversation_as_read(other)
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
    msg = @room.chat_messages.find_by(id: data["message_id"])
    return unless msg && msg.sender == current_delegate

    msg.update!(content: data["content"], edited_at: Time.current)

    ChatRoomChannel.broadcast_to(@room, {
      type: "room_message_updated",
      message_id: msg.id,
      content: msg.content
    })
  end

  # ================= DELETE =================
  def delete_message(data)
    data = parse(data)
    msg = @room.chat_messages.find_by(id: data["message_id"])
    return unless msg && msg.sender == current_delegate

    msg.update!(deleted_at: Time.current, is_deleted: true)

    ChatRoomChannel.broadcast_to(@room, {
      type: "room_message_deleted",
      message_id: msg.id
    })
  end

  # =================================================
  private
  # =================================================

  def parse(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def serializer(msg)
    Api::V1::ChatMessageSerializer
      .new(msg)
      .serializable_hash[:data]
  end

  def redis
    Redis.current
  end

  # ===== USERS =====
  def other_user
    @room.delegates.where.not(id: current_delegate.id).first
  end

  # ===== PRESENCE KEY =====
  def presence_key(viewer_id, target_id)
    "chat_open:#{viewer_id}:#{target_id}"
  end

  # ===== CHECK IF OTHER OPEN =====
  def other_user_open?
    other = other_user
    return false unless other

    redis.get(presence_key(other.id, current_delegate.id)) == "1"
  end

  # ===== AUTO READ WHEN MESSAGE ARRIVE =====
  def auto_read_if_open(msg)
    return unless other_user_open?

    msg.update!(read_at: Time.current)

    ChatRoomChannel.broadcast_to(@room, {
      type: "message_read",
      message_id: msg.id,
      read_at: msg.read_at
    })
  end

  # ===== MARK ALL READ =====
  def mark_conversation_as_read(target_id)
    now = Time.current
    scope = ChatMessage.where(
      sender_id: target_id,
      recipient_id: current_delegate.id,
      read_at: nil,
      deleted_at: nil
    )
    
    # ⭐ Update แล้วได้ ids กลับมาในครั้งเดียว (PostgreSQL)
    ids = scope.update_all(read_at: now).is_a?(Integer) ? 
          scope.pluck(:id) : 
          scope.ids
    
    return if ids.empty?
    
    # ⭐ Broadcast ครั้งเดียว
    ChatChannel.broadcast_to(
      current_delegate,
      type: 'bulk_read',
      message_ids: ids,
      read_at: now
    )
  end







end
