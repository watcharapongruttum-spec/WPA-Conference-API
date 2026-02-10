module Api
  module V1
    class MessagesController < ApplicationController

      # ================= INDEX =================
      # GET /api/v1/messages
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
      # GET /api/v1/messages/conversation/:delegate_id
      def conversation
        other_id = params[:delegate_id]

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
          .order(created_at: :asc)
          .page(params[:page] || 1)
          .per(50)

        render json: @messages, each_serializer: Api::V1::ChatMessageSerializer
      end






      def unread_count
        count = ChatMessage
          .where(recipient: current_delegate, read_at: nil, deleted_at: nil)
          .distinct
          .count(:sender_id)

        render json: { unread_rooms: count }
      end
      def unread_count
        count = ChatMessage
          .where(recipient: current_delegate, read_at: nil, deleted_at: nil)
          .distinct
          .count(:sender_id)

        render json: { unread_rooms: count }
      end







      # ================= CREATE =================
      # POST /api/v1/messages
      def create
        recipient_id = params[:recipient_id] || params[:receiver_id]

        unless recipient_id
          return render json: { error: "recipient_id required" }, status: :unprocessable_entity
        end

        @message = ChatMessage.new(
          sender: current_delegate,
          recipient_id: recipient_id,
          content: params[:content]
        )

        if @message.save
          recipient = @message.recipient

          mark_conversation_as_read(recipient.id)

          if recipient.present?
            # -------- NEW MESSAGE --------
            ChatChannel.broadcast_to(
              recipient,
              type: 'new_message',
              message: Api::V1::ChatMessageSerializer.new(@message).serializable_hash
            )

            # -------- AUTO SEEN --------
            # auto_read_if_open(@message)

            # -------- NOTIFICATION --------
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
                    name: @message.sender.name,
                    avatar_url: Api::V1::DelegateSerializer.new(@message.sender).avatar_url
                  }
                }
              )
            end
          end

          render json: @message, serializer: Api::V1::ChatMessageSerializer, status: :created
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
            read_at: nil
          ).count

          rooms[other.id] = {
            delegate: {
              id: other.id,
              name: other.name,
              title: other.title,
              avatar_url: Api::V1::DelegateSerializer.new(other).avatar_url
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
        messages = current_delegate.received_messages.where(read_at: nil)

        messages.find_each do |msg|
          now = Time.current
          msg.update_column(:read_at, now)

          ChatChannel.broadcast_to(
            msg.sender,
            type: 'message_read',
            message_id: msg.id,
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

        if message.created_at < 30.minutes.ago
          return render json: { error: "Edit time expired" }, status: 422
        end

        if params[:content].blank?
          return render json: { error: "Content cannot be blank" }, status: 422
        end

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

        render json: { success: true }
      end

      # ================= MARK AS READ =================
      def mark_as_read
        message = ChatMessage.find_by(id: params[:id], recipient: current_delegate)

        return render json: { error: 'Message not found' }, status: :not_found unless message

        if message.read_at.present?
          return render json: { message: 'Already read' }, status: :ok
        end

        message.update(read_at: Time.current)

        render json: message, serializer: Api::V1::ChatMessageSerializer
      end

      # ==================================================
      # PRIVATE
      # ==================================================
      private

      def auto_read_if_open(message)
        key = "chat_open:#{message.recipient_id}:#{message.sender_id}"

        Rails.logger.info "CHECK REDIS #{key}"
        value = REDIS.get(key)

        Rails.logger.info "VALUE #{value}"

        return unless value
        return if message.read_at.present?

        now = Time.current
        message.update_column(:read_at, now)

        ChatChannel.broadcast_to(
          message.sender,
          type: 'message_read',
          message_id: message.id,
          read_at: now
        )
      end


      def mark_conversation_as_read(other_user_id)
        unread_messages = ChatMessage.where(
          sender_id: other_user_id,
          recipient_id: current_delegate.id,
          read_at: nil
        )

        now = Time.current

        unread_messages.find_each do |msg|
          msg.update_column(:read_at, now)

          ChatChannel.broadcast_to(
            msg.sender,
            type: 'message_read',
            message_id: msg.id,
            read_at: now
          )
        end
      end




    end
  end
end
