# app/controllers/api/v1/chat_messages_controller.rb
class Api::V1::ChatMessagesController < ApplicationController


  def create
    room = ChatRoom.find(params[:chat_room_id])

    unless room.can_send_message?(current_delegate)
      return render json: { error: "Not allowed" }, status: :forbidden
    end

    message = room.chat_messages.create!(
      sender: current_delegate,
      content: params[:content]
    )

    ChatRoomChannel.broadcast_to(room, message)
    render json: message
  end


  private

  def serialize(message)
    {
      id: message.id,
      content: message.content,
      sender_id: message.sender_id,
      created_at: message.created_at
    }
  end
end
