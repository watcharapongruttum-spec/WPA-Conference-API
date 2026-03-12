# app/controllers/api/v1/chat_rooms_controller.rb
module Api
  module V1
    class ChatRoomsController < ApplicationController
      before_action :set_room, only: %i[destroy join leave]

      def create
        room_attrs = params.require(:chat_room).permit(:title, :room_kind)

        room = ChatRoom.create!(room_attrs)
        room.chat_room_members.create!(delegate: current_delegate, role: :admin)
        AuditLogger.room_created(room, current_delegate, request)

        render json: { id: room.id, title: room.title, room_kind: room.room_kind },
               status: :created
      rescue ActionController::ParameterMissing => e
        render json: { error: "Missing parameter: #{e.param}" }, status: :bad_request
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: "Validation failed", messages: e.record.errors.full_messages },
               status: :unprocessable_entity
      end

      def index
        rooms = current_delegate.chat_rooms
                                .where(deleted_at: nil)
                                .includes(:chat_room_members)
        render json: rooms.map { |room|
          { id: room.id, title: room.title, room_kind: room.room_kind,
            members: room.chat_room_members.pluck(:delegate_id) }
        }
      end

      def destroy
        member = @room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" },   status: :not_found  unless member
        return render json: { error: "Admin only" },   status: :forbidden  unless member.admin?

        @room.update!(deleted_at: Time.current)
        Chat::Group::BroadcastService.room_deleted(@room)
        AuditLogger.room_deleted(@room, current_delegate, request)
        render json: { success: true }
      end

      def join
        return render json: { error: "Room deleted" }, status: :unprocessable_entity if @room.deleted_at.present?

        member   = ChatRoomMember.find_or_initialize_by(chat_room: @room, delegate: current_delegate)
        is_new   = member.new_record?
        member.role ||= :member
        member.save!

        if is_new
          Chat::Group::BroadcastService.member_joined(@room, current_delegate)
          AuditLogger.room_joined(@room, current_delegate, request)
        end

        render json: { success: true, joined: is_new }
      end

      def leave
        member = @room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" }, status: :not_found unless member

        if member.admin? && @room.chat_room_members.where(role: :admin).one?
          return render json: { error: "Last admin cannot leave" }, status: :unprocessable_entity
        end

        member.destroy
        Chat::Group::BroadcastService.member_left(@room, current_delegate.id)
        AuditLogger.room_left(@room, current_delegate, request)
        render json: { success: true }
      end

      private

      def set_room
        @room = ChatRoom.find(params[:id])
      end
    end
  end
end