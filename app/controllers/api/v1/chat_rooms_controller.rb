module Api
  module V1
    class ChatRoomsController < ApplicationController

      # =========================
      # GET /chat_rooms
      # =========================
      def index
        rooms = current_delegate.chat_rooms
                                .where(deleted_at: nil)
                                .includes(:chat_room_members)

        render json: rooms.map { |room|
          {
            id: room.id,
            title: room.title,
            room_kind: room.room_kind,
            members: room.chat_room_members.pluck(:delegate_id)
          }
        }
      end


      # =========================
      # POST /chat_rooms
      # =========================
      def create
        room = ChatRoom.create!(
          title: params[:title],
          room_kind: params[:room_kind]
        )

        # creator เป็น admin อัตโนมัติ
        room.chat_room_members.create!(
          delegate: current_delegate,
          role: :admin
        )

        render json: room, status: :created

      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end


      # =========================
      # DELETE /chat_rooms/:id/leave
      # =========================
      def leave
        room = ChatRoom.find(params[:id])

        member = room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" }, status: 404 unless member

        # กัน admin คนสุดท้ายออก
        if member.admin? && room.chat_room_members.where(role: :admin).count == 1
          return render json: { error: "Last admin cannot leave" }, status: 422
        end

        member.destroy

        ChatRoomChannel.broadcast_to(
          room,
          type: "member_left",
          delegate_id: current_delegate.id
        )

        render json: { success: true }
      end


      # =========================
      # DELETE /chat_rooms/:id
      # =========================
      def destroy
        room = ChatRoom.find(params[:id])

        member = room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" }, status: 404 unless member
        return render json: { error: "Admin only" }, status: 403 unless member.admin?
        return render json: { error: "Already deleted" }, status: 422 if room.deleted_at.present?


        # Soft delete
        room.update!(deleted_at: Time.current)

        ChatRoomChannel.broadcast_to(
          room,
          type: "room_deleted",
          room_id: room.id
        )

        render json: { success: true }
      end

    end
  end
end



