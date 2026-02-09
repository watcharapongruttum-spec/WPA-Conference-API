# app/controllers/api/v1/messages_controller.rb
module Api
  module V1
    class MessagesController < ApplicationController
      
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
          # @message.update(read_at: Time.current)

          recipient = @message.recipient

          if recipient.present?
            ChatChannel.broadcast_to(
              recipient,
              type: 'new_message',
              message: Api::V1::ChatMessageSerializer.new(@message).serializable_hash
            )

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
                  content: @message.content.truncate(50),
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
          render json: { error: 'Failed to send message', errors: @message.errors.full_messages }, status: :unprocessable_entity
        end
      end


      



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







      def read_all
        messages = current_delegate.received_messages.where(read_at: nil)

        messages.find_each do |msg|
          now = Time.current
          msg.update_column(:read_at, now)

          payload = {
            type: 'message_read',
            message_id: msg.id,
            read_at: now
          }

          ChatChannel.broadcast_to(msg.sender, payload)
        end

        render json: { message: "All messages marked as read" }
      end











      def update
        message = ChatMessage.find(params[:id])

        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Message deleted" }, status: 422 if message.deleted?

        # กันแก้เกินเวลา
        if message.created_at < 30.minutes.ago
          return render json: { error: "Edit time expired" }, status: 422
        end

        # กัน content ว่าง
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

        if message.chat_room
          ChatRoomChannel.broadcast_to(message.chat_room, payload)
        else
          ChatChannel.broadcast_to(message.recipient, payload)
        end

        render json: { success: true }
      end






      def destroy
        message = ChatMessage.find(params[:id])

        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Already deleted" }, status: 422 if message.deleted?

        message.update!(deleted_at: Time.current)

        payload = {
          type: "message_deleted",
          message_id: message.id
        }

        if message.chat_room
          ChatRoomChannel.broadcast_to(message.chat_room, payload)
        else
          ChatChannel.broadcast_to(message.recipient, payload)
        end

        render json: { success: true }
      end












      
      # PATCH /api/v1/messages/:id/mark_as_read
      def mark_as_read
        # 🔥 FIX: Find message where current user is RECIPIENT
        @message = ChatMessage.find_by(id: params[:id], recipient: current_delegate)
        
        if @message.nil?
          # Try to find if user is sender (already read)
          sender_message = ChatMessage.find_by(id: params[:id], sender: current_delegate)
          
          if sender_message
            render json: { 
              error: 'Cannot mark your own sent message as read',
              message: 'This message is already marked as read because you are the sender'
            }, status: :unprocessable_entity
            return
          else
            render json: { error: 'Message not found or you are not the recipient' }, status: :not_found
            return
          end
        end
        
        # 🔥 FIX: Check if already read
        if @message.read_at.present?
          render json: { 
            message: 'Message already marked as read',
            data: Api::V1::ChatMessageSerializer.new(@message).serializable_hash
          }, status: :ok
          return
        end
        
        if @message.update(read_at: Time.current)
          render json: @message, serializer: Api::V1::ChatMessageSerializer
        else
          render json: { 
            error: 'Failed to mark message as read',
            errors: @message.errors.full_messages
          }, status: :unprocessable_entity
        end
      end
    end
  end
end
