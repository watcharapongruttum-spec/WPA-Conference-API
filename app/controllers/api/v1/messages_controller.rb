# app/controllers/api/v1/messages_controller.rb
module Api
  module V1
    class MessagesController < ApplicationController
      
      # GET /api/v1/messages
      def index
        @messages = ChatMessage.where(sender: current_delegate)
                               .or(ChatMessage.where(recipient: current_delegate))
                               .includes(:sender, :recipient)
                               .order(created_at: :desc)
                               .page(params[:page] || 1)
                               .per(50)
        
        render json: @messages, each_serializer: Api::V1::ChatMessageSerializer
      end
      
      # GET /api/v1/messages/conversation/:delegate_id
      def conversation
        other_delegate_id = params[:delegate_id]
        
        @messages = ChatMessage.where(
          "(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)",
          current_delegate.id, other_delegate_id,
          other_delegate_id, current_delegate.id
        ).includes(:sender, :recipient)
         .order(created_at: :asc)
         .page(params[:page] || 1)
         .per(50)
        
        render json: @messages, each_serializer: Api::V1::ChatMessageSerializer
      end
      
      # POST /api/v1/messages
      def create
        @message = ChatMessage.new(
          sender: current_delegate,
          recipient_id: params[:recipient_id],
          content: params[:content]
        )
        
        if @message.save
          # ทำเครื่องหมายว่าอ่านแล้วสำหรับผู้ส่ง
          @message.update(read_at: Time.current) if @message.sender == current_delegate
          
          # 🔥 เพิ่มการ broadcast ไปยังผู้รับผ่าน WebSocket
          ChatChannel.broadcast_to(
            @message.recipient,
            type: 'new_message',
            message: Api::V1::ChatMessageSerializer.new(@message).serializable_hash
          )
          
          # 🔥 สร้างและส่งการแจ้งเตือนเรียลไทม์
          notification = Notification.create!(
            delegate: @message.recipient,
            notification_type: 'new_message',
            notifiable: @message
          )
          
          NotificationChannel.broadcast_to(
            @message.recipient,
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
          
          render json: @message, serializer: Api::V1::ChatMessageSerializer, status: :created
        else
          render json: { 
            error: 'Failed to send message', 
            errors: @message.errors.full_messages 
          }, status: :unprocessable_entity
        end
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
