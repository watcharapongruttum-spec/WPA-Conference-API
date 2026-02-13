module Api
  module V1
    class MessagesController < ApplicationController

      # ================= INDEX =================
      def index
        @messages = ChatMessage
          .where(deleted_at: nil)
          .where("sender_id = :me OR recipient_id = :me", me: current_delegate.id)
          .includes(:sender, :recipient)
          .order(created_at: :desc)
          .page(params[:page] || 1)
          .per(50)

        render json: @messages, each_serializer: Api::V1::ChatMessageSerializer
      end

      # ================= CONVERSATION =================
      def conversation
        other_id = params[:delegate_id]
        page = (params[:page] || 1).to_i
        per  = (params[:per]  || 50).to_i

        @messages = ChatMessage
          .where(deleted_at: nil)
          .where(
            "(sender_id = :me AND recipient_id = :other)
            OR
            (sender_id = :other AND recipient_id = :me)",
            me: current_delegate.id,
            other: other_id
          )
          .includes(:sender, :recipient)
          .order(created_at: :desc)
          .page(page)
          .per(per)

        render json: {
          data: ActiveModelSerializers::SerializableResource.new(
            @messages,
            each_serializer: Api::V1::ChatMessageSerializer
          ),
          meta: {
            page: page,
            per: per,
            total_pages: @messages.total_pages,
            total_count: @messages.total_count
          }
        }
      end


      # ================= UNREAD COUNT (TOTAL MESSAGE) =================
      def unread_count
        count = ChatMessage.where(
          recipient_id: current_delegate.id,
          sender_id: params[:sender_id], # เพิ่มบรรทัดนี้
          read_at: nil,
          deleted_at: nil
        ).count


        render json: { unread_count: count }
      end

      # ================= CREATE =================
      def create
        recipient_id = params[:recipient_id] || params[:receiver_id]
        return render json: { error: "recipient_id required" }, status: :unprocessable_entity unless recipient_id

        @message = ChatMessage.new(
          sender: current_delegate,
          recipient_id: recipient_id,
          content: params[:content]
        )

        if @message.save
          recipient = @message.recipient
          now = Time.current

          # ================= AUTO SEEN =================
          key = "chat_open:#{recipient.id}:#{current_delegate.id}"

          if REDIS.get(key) == "1"

            # ---- 1. mark message ล่าสุด ----
            @message.update_column(:read_at, now) if @message.read_at.nil?

            # ---- 2. mark message เก่าทั้งห้อง ----
            scope = ChatMessage.where(
              sender_id: current_delegate.id,
              recipient_id: recipient.id,
              read_at: nil,
              deleted_at: nil
            )

            ids = scope.pluck(:id)
            scope.update_all(read_at: now) unless ids.empty?

            # ---- 3. broadcast ทีเดียว ----
            payload_seen = {
              type: 'bulk_read',
              message_ids: ids + [@message.id],
              read_at: now
            }

            ChatChannel.broadcast_to(recipient, payload_seen)
            ChatChannel.broadcast_to(current_delegate, payload_seen)
          end

          # ================= NEW MESSAGE =================
          payload = {
            type: 'new_message',
            message: Api::V1::ChatMessageSerializer.new(@message).serializable_hash
          }

          ChatChannel.broadcast_to(recipient, payload)
          ChatChannel.broadcast_to(current_delegate, payload)

          # ================= NOTIFICATION =================
          notification = Notification.create(
            delegate: recipient,
            notification_type: 'new_message',
            notifiable: @message
          )

          if notification
            NotificationChannel.broadcast_to(
              recipient,
              type: 'new_notification',
              notification: {
                id: notification.id,
                type: 'new_message',
                created_at: notification.created_at,
                content: @message.content.to_s.truncate(50),
                sender: {
                  id: @message.sender.id,
                  name: @message.sender.name
                }
              }
            )
          end

          
          render json: @message,
                serializer: Api::V1::ChatMessageSerializer,
                status: :created
        else
          render json: {
            error: 'Failed to send message',
            errors: @message.errors.full_messages
          }, status: :unprocessable_entity
        end
      end


      # ================= ROOMS =================
      def rooms
        me = current_delegate

        messages = ChatMessage
          .where(deleted_at: nil)
          .where("sender_id = ? OR recipient_id = ?", me.id, me.id)
          .includes(:sender, :recipient)
          .order(created_at: :desc)

        rooms = {}

        messages.each do |msg|
          other = msg.sender_id == me.id ? msg.recipient : msg.sender
          next if other.nil?
          next if rooms[other.id]

          unread_count = ChatMessage.where(
            sender_id: other.id,
            recipient_id: me.id,
            read_at: nil,
            deleted_at: nil
          ).count

          rooms[other.id] = {
            delegate: {
              id: other.id,
              name: other.name,
              title: other.title
            },
            last_message: msg.content,
            last_message_at: msg.created_at,
            unread_count: unread_count
          }
        end

        render json: rooms.values
      end

      # ================= READ ALL =================
      def read_all
        messages = current_delegate.received_messages
          .where(read_at: nil, deleted_at: nil)

        now = Time.current
        ids = messages.pluck(:id, :sender_id)

        messages.update_all(read_at: now)

        ids.each do |msg_id, sender_id|
          ChatChannel.broadcast_to(
            Delegate.find(sender_id),
            type: 'message_read',
            message_id: msg_id,
            read_at: now
          )
        end

        render json: { message: "All messages marked as read" }
      end


      # ================= UPDATE =================
      def update
        message = ChatMessage.find(params[:id])

        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Message deleted" }, status: 422 if message.deleted?
        return render json: { error: "Content cannot be blank" }, status: 422 if params[:content].blank?

        message.update!(
          content: params[:content],
          edited_at: Time.current
        )

        payload = {
          type: "message_updated",
          message_id: message.id,
          content: message.content,
          edited_at: message.edited_at
        }

        ChatChannel.broadcast_to(message.recipient, payload)
        ChatChannel.broadcast_to(message.sender, payload)

        render json: { success: true }
      end

      # ================= DESTROY =================
      def destroy
        message = ChatMessage.find(params[:id])

        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Already deleted" }, status: 422 if message.deleted?

        message.update!(deleted_at: Time.current)

        payload = {
          type: "message_deleted",
          message_id: message.id
        }

        ChatChannel.broadcast_to(message.recipient, payload)
        ChatChannel.broadcast_to(message.sender, payload)

        render json: { success: true }
      end

      private
    end
  end
end
