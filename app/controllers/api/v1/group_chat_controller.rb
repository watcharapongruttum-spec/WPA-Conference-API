# app/controllers/api/v1/group_chat_controller.rb
module Api
  module V1
    class GroupChatController < ApplicationController
      before_action :set_room,      except: %i[index create_room]
      before_action :verify_member, except: %i[index create_room join]

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
        member_ids = Array(params[:member_ids]).map(&:to_i).uniq
        member_ids -= [current_delegate.id]

        total = member_ids.size + 1
        if total < 3
          return render json: {
            error: "Group chat requires at least 3 members (got #{total})"
          }, status: :unprocessable_entity
        end

        title = params[:title].to_s.strip
        if title.blank?
          return render json: { error: "Title cannot be blank" },
                        status: :unprocessable_entity
        end

        room = ChatRoom.create!(title: title, room_kind: :group)

        room.chat_room_members.create!(delegate_id: current_delegate.id, role: :admin)

        valid_ids = Delegate.where(id: member_ids).pluck(:id)
        valid_ids.each do |id|
          room.chat_room_members.create!(delegate_id: id, role: :member)
        end

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

        @room.chat_room_members.create!(delegate_id: current_delegate.id, role: :member)
        render json: { success: true, room_id: @room.id }
      end

      # DELETE /api/v1/group_chat/:id/leave
      def leave
        member = @room.chat_room_members.find_by(delegate_id: current_delegate.id)
        return render json: { error: "Not a member" }, status: :unprocessable_entity unless member

        if member.role == "admin" && @room.chat_room_members.where(role: :admin).one?
          return render json: { error: "Last admin cannot leave" },
                        status: :unprocessable_entity
        end

        member.destroy
        GroupChatChannel.broadcast_to(@room, type: "member_left", delegate_id: current_delegate.id)
        AuditLogger.room_left(@room, current_delegate, request)
        render json: { success: true }
      end

      # DELETE /api/v1/group_chat/:id
      def destroy_room
        unless @room.chat_room_members.find_by(delegate_id: current_delegate.id)&.role == "admin"
          return render json: { error: "Admin only" }, status: :forbidden
        end

        @room.update!(deleted_at: Time.current)
        GroupChatChannel.broadcast_to(@room, type: "room_deleted", room_id: @room.id)
        AuditLogger.room_deleted(@room, current_delegate, request)
        render json: { success: true }
      end

      # GET /api/v1/group_chat/:id/messages
      def messages
        return render json: { error: "Room has been deleted" }, status: :gone if @room.deleted_at.present?

        page = (params[:page] || 1).to_i
        per  = [(params[:per] || 50).to_i, 100].min

        msgs = @room.chat_messages
                    .where(deleted_at: nil)
                    .includes(:sender, message_reads: :delegate)
                    .order(created_at: :desc)
                    .page(page).per(per)

        render json: {
          data: msgs.map { |m| GroupChat::MessageSerializer.call(message: m, sender: m.sender) },
          meta: {
            page:        page,
            per:         per,
            total_pages: msgs.total_pages,
            total_count: msgs.total_count
          }
        }
      end

      # POST /api/v1/group_chat/:id/messages
      def send_message
        # ✅ ส่งรูปภาพ
        if params[:image].present?
          msg = @room.chat_messages.create!(
            sender:       current_delegate,
            content:      "",
            message_type: "image"
          )

          Chat::ImageService.attach(message: msg, data_uri: params[:image])
          msg.reload
          MessageRead.mark_for(delegate: current_delegate, message_ids: [msg.id])

          serialized = GroupChat::MessageSerializer.call(message: msg, sender: current_delegate)
          GroupChatChannel.broadcast_to(@room, { type: "group_message", room_id: @room.id, message: serialized })

          return render json: serialized, status: :created
        end

        # ✅ ส่งข้อความ
        content = params[:content].to_s.strip

        if content.blank?
          return render json: { error: "Content cannot be blank" }, status: :unprocessable_entity
        end

        if content.length > 2000
          return render json: { error: "Content too long (max 2000)" }, status: :unprocessable_entity
        end

        msg = @room.chat_messages.create!(
          sender:       current_delegate,
          content:      content,
          message_type: "text"
        )

        MessageRead.mark_for(delegate: current_delegate, message_ids: [msg.id])
        serialized = GroupChat::MessageSerializer.call(message: msg, sender: current_delegate)

        GroupChatChannel.broadcast_to(@room, { type: "group_message", room_id: @room.id, message: serialized })

        render json: serialized, status: :created
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      # GET /api/v1/group_chat/:id/readers/:message_id
      def readers
        message = @room.chat_messages.find_by(id: params[:message_id])
        return render json: { error: "Message not found" }, status: :not_found unless message

        readers = MessageRead
                  .includes(:delegate)
                  .where(chat_message_id: message.id)
                  .where.not(delegate_id: message.sender_id)
                  .map do |mr|
                    DelegatePresenter.minimal(mr.delegate)
                      &.merge(read_at: TimeFormatter.format(mr.read_at))
                  end.compact

        render json: {
          message_id:    message.id,
          total_members: @room.chat_room_members.count,
          read_count:    readers.size + 1,
          readers:       readers
        }
      end

      private

      def set_room
        @room = ChatRoom.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Room not found" }, status: :not_found
      end

      def verify_member
        return if @room.chat_room_members.exists?(delegate_id: current_delegate.id)

        render json: { error: "Not a member of this room" }, status: :forbidden
      end

      def serialize_room(room)
        {
          id:           room.id,
          title:        room.title,
          member_count: room.chat_room_members.count,
          created_at:   TimeFormatter.format(room.created_at),
          members:      room.chat_room_members.includes(:delegate).map do |m|
                          DelegatePresenter.minimal(m.delegate)
                            &.merge(role: m.role)
                        end.compact
        }
      end
    end
  end
end