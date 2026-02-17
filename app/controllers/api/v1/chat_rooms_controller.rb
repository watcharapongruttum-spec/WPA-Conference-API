module Api
  module V1
    class ChatRoomsController < ApplicationController
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
        room = ChatRoom.create!(
          title: params[:title],
          room_kind: params[:room_kind]
        )
        
        room.chat_room_members.create!(
          delegate: current_delegate,
          role: :admin
        )
        
        # ⭐ AUDIT LOG
        AuditLogger.room_created(room, current_delegate, request)
        
        render json: room, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # ================= DESTROY =================
      def destroy
        room = ChatRoom.find(params[:id])
        member = room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" }, status: 404 unless member
        return render json: { error: "Admin only" }, status: 403 unless member.admin?
        return render json: { error: "Already deleted" }, status: 422 if room.deleted_at.present?
        
        room.update!(deleted_at: Time.current)
        
        ChatRoomChannel.broadcast_to(
          room,
          type: "room_deleted",
          room_id: room.id
        )
        
        # ⭐ AUDIT LOG
        AuditLogger.room_deleted(room, current_delegate, request)
        
        render json: { success: true }
      end

      # ================= JOIN =================
      def join
        room = ChatRoom.find(params[:id])
        if room.deleted_at.present?
          return render json: { error: "Room deleted" }, status: :unprocessable_entity
        end
        
        member = ChatRoomMember.find_or_initialize_by(
          chat_room: room,
          delegate: current_delegate
        )
        is_new_member = member.new_record?
        member.role ||= :member
        member.save!
        
        if is_new_member
          ChatRoomChannel.broadcast_to(
            room,
            type: "member_joined",
            delegate: {
              id: current_delegate.id,
              name: current_delegate.name,
              avatar_url: current_delegate.avatar_url
            }
          )
          
          # ⭐ AUDIT LOG
          AuditLogger.room_joined(room, current_delegate, request)
        end
        
        render json: { success: true, joined: is_new_member }
      end

      # ================= LEAVE =================
      def leave
        room = ChatRoom.find(params[:id])
        member = room.chat_room_members.find_by(delegate: current_delegate)
        return render json: { error: "Not member" }, status: 404 unless member
        
        if member.admin? && room.chat_room_members.where(role: :admin).count == 1
          return render json: { error: "Last admin cannot leave" }, status: 422
        end
        
        member.destroy
        
        ChatRoomChannel.broadcast_to(
          room,
          type: "member_left",
          delegate_id: current_delegate.id
        )
        
        # ⭐ AUDIT LOG
        AuditLogger.room_left(room, current_delegate, request)
        
        render json: { success: true }
      end
    end
  end
end