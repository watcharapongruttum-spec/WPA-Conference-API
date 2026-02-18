module Api
  module V1
    class ChatRoomsController < ApplicationController
      before_action :set_room, only: [:destroy, :join, :leave]

      # ================= INDEX =================
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



      # ================= CREATE =================
      def create
        params = room_params
        return unless params

        room = ChatRoom.create!(params)

        room.chat_room_members.create!(
          delegate: current_delegate,
          role: :admin
        )

        AuditLogger.room_created(room, current_delegate, request)

        render json: {
          id: room.id,
          title: room.title,
          room_kind: room.room_kind
        }, status: :created

      rescue ActiveRecord::RecordInvalid => e
        render json: {
          error: "Validation failed",
          messages: e.record.errors.full_messages
        }, status: :unprocessable_entity
      end


      # ================= DESTROY =================
      def destroy
        member = @room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" }, status: :not_found unless member
        return render json: { error: "Admin only" }, status: :forbidden unless member.admin?
        return render json: { error: "Already deleted" }, status: :unprocessable_entity if @room.deleted_at.present?

        @room.update!(deleted_at: Time.current)

        ChatRoomChannel.broadcast_to(
          @room,
          type: "room_deleted",
          room_id: @room.id
        )

        AuditLogger.room_deleted(@room, current_delegate, request)

        render json: { success: true }
      end

      # ================= JOIN =================
      def join
        return render json: { error: "Room deleted" }, status: :unprocessable_entity if @room.deleted_at.present?

        member = ChatRoomMember.find_or_initialize_by(
          chat_room: @room,
          delegate: current_delegate
        )

        is_new_member = member.new_record?
        member.role ||= :member
        member.save!

        if is_new_member
          ChatRoomChannel.broadcast_to(
            @room,
            type: "member_joined",
            delegate: {
              id: current_delegate.id,
              name: current_delegate.name,
              avatar_url: current_delegate.avatar_url
            }
          )

          AuditLogger.room_joined(@room, current_delegate, request)
        end

        render json: { success: true, joined: is_new_member }
      end

      # ================= LEAVE =================
      def leave
        member = @room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" }, status: :not_found unless member

        if member.admin? && @room.chat_room_members.where(role: :admin).count == 1
          return render json: { error: "Last admin cannot leave" }, status: :unprocessable_entity
        end

        member.destroy

        ChatRoomChannel.broadcast_to(
          @room,
          type: "member_left",
          delegate_id: current_delegate.id
        )

        AuditLogger.room_left(@room, current_delegate, request)

        render json: { success: true }
      end

      private

      # ================= STRONG PARAMS =================
      def room_params
        params.require(:chat_room).permit(:title, :room_kind)
      rescue ActionController::ParameterMissing => e
        render json: {
          error: "Missing parameter: #{e.param}"
        }, status: :bad_request
        nil
      end


      # ================= CALLBACK =================
      def set_room
        @room = ChatRoom.find(params[:id])
      end
    end
  end
end
