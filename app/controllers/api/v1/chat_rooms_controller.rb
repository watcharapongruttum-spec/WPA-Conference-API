module Api
  module V1
    class ChatRoomsController < ApplicationController


      def index
        rooms = current_delegate.chat_rooms.includes(:chat_room_members)

        render json: rooms.map { |room|
          {
            id: room.id,
            room_kind: room.room_kind,
            members: room.chat_room_members.pluck(:delegate_id)
          }
        }
      end
    end
  end
end
