class GroupChatChannel < ApplicationCable::Channel
  def subscribed
    @room = ChatRoom.find(params[:room_id])

    unless @room.chat_room_members.exists?(delegate_id: current_delegate.id)
      reject
      return
    end

    stream_for @room
  end

  def speak(data)
    message = @room.chat_messages.create!(
      sender: current_delegate,
      content: data["content"]
    )

    GroupChatChannel.broadcast_to(@room, {
      id: message.id,
      room_id: @room.id,
      sender_id: current_delegate.id,
      content: message.content,
      created_at: message.created_at
    })
  end
end
