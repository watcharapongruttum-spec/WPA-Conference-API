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
        @message = ChatMessage.find_by(id: params[:id], recipient: current_delegate)
        
        if @message.nil?
          render json: { error: 'Message not found' }, status: :not_found
          return
        end
        
        if @message.mark_as_read!
          render json: @message, serializer: Api::V1::ChatMessageSerializer
        else
          render json: { error: 'Failed to mark message as read' }, status: :unprocessable_entity
        end
      end
    end
  end
end