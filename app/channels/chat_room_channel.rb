class ChatRoomChannel < ApplicationCable::Channel
  def subscribed
    @room = ChatRoom.find(params[:room_id])
    reject unless @room.delegates.include?(current_delegate)

    stream_for @room
  end

  def send_message(data)
    @room.chat_messages.create!(
      sender: current_delegate,
      content: data["content"]
    )
    # ❌ ไม่ broadcast ที่นี่ → model จัดการให้
  end
end
