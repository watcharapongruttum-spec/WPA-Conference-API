# app/controllers/api/v1/chat_messages_controller.rb
class Api::V1::ChatMessagesController < ApplicationController
  def create
    room = ChatRoom.find(params[:chat_room_id])

    return render json: { error: "Not allowed" }, status: :forbidden unless room.can_send_message?(current_delegate)

    message = room.chat_messages.create!(
      sender: current_delegate,
      content: params[:content]
    )

    serialized = Api::V1::ChatMessageSerializer
                 .new(message)
                 .serializable_hash[:data]

    ChatRoomChannel.broadcast_to(room, {
                                   type: "room_message",
                                   room_id: room.id,
                                   message: serialized
                                 })

    render json: message, serializer: Api::V1::ChatMessageSerializer
  end
end
