# app/controllers/api/v1/group_chat_controller.rb
module Api
  module V1
    class GroupChatController < ApplicationController
      before_action :set_room,      except: [:index, :create_room]
      before_action :verify_member, except: [:index, :create_room, :join]

      # GET /api/v1/group_chat
      def index
        rooms = current_delegate.chat_room_members
                                .joins(:chat_room)
                                .where(chat_rooms: { deleted_at: nil, room_kind: :group })
                                .includes(chat_room: :chat_room_members)
                                .map { |m| serialize_room(m.chat_room) }

        render json: { data: rooms }
      end

      # POST /api/v1/group_chat
      def create_room
        room = ChatRoom.create!(
          title:     params[:title],
          room_kind: :group
        )

        room.chat_room_members.create!(
          delegate_id: current_delegate.id,
          role:        :admin
        )

        render json: serialize_room(room), status: :created

      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      end

      # POST /api/v1/group_chat/:id/join
      def join
        if @room.chat_room_members.exists?(delegate_id: current_delegate.id)
          return render json: { error: "Already a member" }, status: :unprocessable_entity
        end

        @room.chat_room_members.create!(
          delegate_id: current_delegate.id,
          role:        :member
        )

        render json: { success: true, room_id: @room.id }
      end

      # DELETE /api/v1/group_chat/:id/leave
      def leave
        member = @room.chat_room_members.find_by(delegate_id: current_delegate.id)
        return render json: { error: "Not a member" }, status: :unprocessable_entity unless member

        if member.role == "admin" &&
           @room.chat_room_members.where(role: :admin).count == 1
          return render json: { error: "Last admin cannot leave" },
                        status: :unprocessable_entity
        end

        member.destroy
        render json: { success: true }
      end

      # DELETE /api/v1/group_chat/:id
      def destroy_room
        unless @room.chat_room_members.find_by(delegate_id: current_delegate.id)&.role == "admin"
          return render json: { error: "Admin only" }, status: :forbidden
        end

        @room.update!(deleted_at: Time.current)
        render json: { success: true }
      end

      # GET /api/v1/group_chat/:id/messages
      def messages
        page = (params[:page] || 1).to_i
        per  = [(params[:per] || 50).to_i, 100].min

        msgs = @room.chat_messages
                    .where(deleted_at: nil)
                    .includes(:sender)
                    .order(created_at: :desc)
                    .page(page).per(per)

        render json: {
          data: msgs.map { |m| serialize_message(m) },
          meta: {
            page:        page,
            per:         per,
            total_pages: msgs.total_pages,
            total_count: msgs.total_count
          }
        }
      end

      # POST /api/v1/group_chat/:id/messages
      # REST fallback — ใช้ตอน WebSocket ไม่ได้เชื่อม
      def send_message
        content = params[:content].to_s.strip

        return render json: { error: "Content cannot be blank" },
                      status: :unprocessable_entity if content.blank?

        return render json: { error: "Content too long (max 2000)" },
                      status: :unprocessable_entity if content.length > 2000

        msg = @room.chat_messages.create!(
          sender:  current_delegate,
          content: content
        )

        # Broadcast เหมือน GroupChatChannel#speak
        GroupChatChannel.broadcast_to(@room, {
          type:    "group_message",
          room_id: @room.id,
          message: serialize_message(msg)
        })

        # Push หา member ที่ offline
        push_to_offline_members(msg)

        render json: serialize_message(msg), status: :created

      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      end

      private

      def set_room
        @room = ChatRoom.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Room not found" }, status: :not_found
      end

      def verify_member
        unless @room.chat_room_members.exists?(delegate_id: current_delegate.id)
          render json: { error: "Not a member of this room" }, status: :forbidden
        end
      end

      def serialize_room(room)
        {
          id:           room.id,
          title:        room.title,
          member_count: room.chat_room_members.count,
          created_at:   room.created_at
        }
      end

      def serialize_message(msg)
        sender = msg.sender
        {
          id:         msg.id,
          content:    msg.deleted_at? ? nil : msg.content,
          created_at: msg.created_at,
          edited_at:  msg.edited_at,
          deleted_at: msg.deleted_at,
          is_deleted: msg.deleted_at?,
          is_edited:  msg.edited_at?,
          read_at:    msg.read_at,
          sender: {
            id:           sender&.id,
            name:         sender&.name,
            title:        sender&.title,
            company_name: sender&.company&.name,
            avatar_url:   sender&.avatar_url
          }
        }
      end

      def push_to_offline_members(msg)
        member_ids = @room.chat_room_members
                          .where.not(delegate_id: current_delegate.id)
                          .pluck(:delegate_id)

        member_ids.each do |delegate_id|
          room_open = REDIS.get("group_chat_open:#{@room.id}:#{delegate_id}") == "1"
          online    = Chat::PresenceService.online?(delegate_id)

          Rails.logger.info "[GroupChat] delegate=#{delegate_id} room_open=#{room_open} online=#{online}"

          next if room_open
          next if online

          Rails.logger.info "[GroupChat] → enqueue GroupMessagePushJob for delegate=#{delegate_id}"

          GroupMessagePushJob.perform_later(
            delegate_id: delegate_id,
            room_id:     @room.id,
            room_title:  @room.title,
            sender_name: current_delegate.name,
            content:     msg.content
          )
        end
      end
    end
  end
end