class ChatRoomChannel < ApplicationCable::Channel
  def subscribed
    @room = ChatRoom.find(params[:room_id])
    reject unless @room.delegates.include?(current_delegate)

    stream_for @room
  end

  # ================= SEND =================
  def send_message(data)
    data = parse(data)

    msg = @room.chat_messages.create!(
      sender: current_delegate,
      content: data["content"]
    )

    ChatRoomChannel.broadcast_to(@room, {
      type: "room_message",
      room_id: @room.id,
      message: serializer(msg)
    })
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

  private

  def parse(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def serializer(msg)
    Api::V1::ChatMessageSerializer
      .new(msg)
      .serializable_hash[:data]
  end
end
