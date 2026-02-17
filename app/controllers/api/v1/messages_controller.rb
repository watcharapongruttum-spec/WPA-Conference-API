module Api
  module V1
    class MessagesController < ApplicationController
      # ================= INDEX =================
      def index
        @messages = ChatMessage
          .not_deleted
          .where("sender_id = :me OR recipient_id = :me", me: current_delegate.id)
          .includes(:sender, :recipient)
          .order(created_at: :desc)
          .page(params[:page] || 1)
          .per([params[:per].to_i, 100].min)  # ⭐ จำกัด max per page
        render json: @messages, each_serializer: Api::V1::ChatMessageSerializer
      end

      # ================= CONVERSATION =================
      def conversation
        other_id = params[:delegate_id]
        page = (params[:page] || 1).to_i
        per  = [(params[:per]  || 50).to_i, 100].min  # ⭐ จำกัด max per page
        
        @messages = ChatMessage
          .not_deleted
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

      # ================= ROOMS (OPTIMIZED) =================
      def rooms
        me = current_delegate
        
        # ⭐ QUERY เดียวได้ unread_count ทั้งหมด
        unread_counts = ChatMessage
          .select('sender_id, recipient_id, COUNT(*) as count')
          .where(recipient_id: me.id, read_at: nil, deleted_at: nil)
          .group(:sender_id, :recipient_id)
          .pluck(:sender_id, :recipient_id, :count)
        
        unread_hash = unread_counts.each_with_object({}) do |(sender_id, recipient_id, count), h|
          other_id = sender_id == me.id ? recipient_id : sender_id
          h[other_id] = count
        end
        
        # ⭐ QUERY ครั้งเดียวได้ last message ทั้งหมด
        messages = ChatMessage
          .select('DISTINCT ON (CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END) *', me.id)
          .not_deleted
          .where("sender_id = ? OR recipient_id = ?", me.id, me.id)
          .includes(:sender, :recipient)
          .order('CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END, created_at DESC', me.id)
        
        rooms = messages.each_with_object({}) do |msg, h|
          other = msg.sender_id == me.id ? msg.recipient : msg.sender
          next if other.nil? || h[other.id]
          
          h[other.id] = {
            delegate: {
              id: other.id,
              name: other.name,
              title: other.title
            },
            last_message: msg.content,
            last_message_at: msg.created_at,
            unread_count: unread_hash[other.id] || 0
          }
        end
        
        render json: rooms.values
      end
      



      # # ================= CONVERSATION =================
      # def conversation
      #   other_id = params[:delegate_id]
      #   # ⭐ จำกัด per max 100
      #   page = [(params[:page] || 1).to_i, 1].max
      #   per  = [(params[:per] || 50).to_i, 100].min
        
      #   @messages = ChatMessage
      #     .not_deleted
      #     .where(
      #       "(sender_id = :me AND recipient_id = :other)
      #       OR (sender_id = :other AND recipient_id = :me)",
      #       me: current_delegate.id,
      #       other: other_id
      #     )
      #     .includes(:sender, :recipient)
      #     .order(created_at: :desc)
      #     .page(page)
      #     .per(per)
          
      #   render json: {
      #     data: ActiveModelSerializers::SerializableResource.new(
      #       @messages,
      #       each_serializer: Api::V1::ChatMessageSerializer
      #     ),
      #     meta: {
      #       page: page,
      #       per: per,
      #       total_pages: @messages.total_pages,
      #       total_count: @messages.total_count
      #     }
      #   }
      # end







      # ================= CREATE =================
      def create
        recipient_id = params[:recipient_id] || params[:receiver_id]
        return render json: { error: "recipient_id required" }, status: :unprocessable_entity unless recipient_id
        
        # ===== VALIDATE CONTENT LENGTH =====
        if params[:content].blank?
          return render json: { 
            error: "Validation failed", 
            details: { content: ["cannot be blank"] } 
          }, status: :unprocessable_entity
        end
        
        if params[:content].length > 2000
          return render json: { 
            error: "Validation failed", 
            details: { content: ["must be between 1 and 2000 characters"] } 
          }, status: :unprocessable_entity
        end
        
        @message = Chat::SendMessageService.call(
          sender: current_delegate,
          recipient_id: recipient_id,
          content: params[:content]
        )
        
        # ⭐ AUDIT LOG (ถ้ามี)
        if defined?(AuditLogger)
          AuditLogger.message_created(@message, request)
        end
        
        render json: @message,
          serializer: Api::V1::ChatMessageSerializer,
          status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { 
          error: "Validation failed", 
          details: e.record.errors.full_messages 
        }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error "[MessagesController#create] #{e.class}: #{e.message}"
        render json: { 
          error: "Failed to create message", 
          details: Rails.env.development? ? e.message : nil 
        }, status: :internal_server_error
      end






      # ================= UPDATE =================
      def update
        message = ChatMessage.find(params[:id])
        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Message deleted" }, status: 422 if message.deleted?
        return render json: { error: "Content cannot be blank" }, status: 422 if params[:content].blank?
        
        old_content = message.content
        Chat::UpdateMessageService.call(
          message: message,
          content: params[:content]
        )
        
        # ⭐ AUDIT LOG
        AuditLogger.message_updated(message, { old_content: old_content, new_content: params[:content] }, request)
        
        render json: { success: true }
      end

      # ================= DESTROY =================
      def destroy
        message = ChatMessage.find(params[:id])
        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Already deleted" }, status: 422 if message.deleted?
        
        Chat::DeleteMessageService.call(message: message)
        
        # ⭐ AUDIT LOG
        AuditLogger.message_deleted(message, request)
        
        render json: { success: true }
      end

      # ================= READ ALL =================
      def read_all
        Chat::ReadService.read_all(current_delegate)
        render json: { message: "All messages marked as read" }
      end

      # ================= UNREAD COUNT =================
      def unread_count
        count = ChatMessage.where(
          recipient_id: current_delegate.id,
          sender_id: params[:sender_id],
          read_at: nil,
          deleted_at: nil
        ).count
        render json: { unread_count: count }
      end

      def online_status
        user_id = params[:user_id]
        online = Chat::PresenceService.online?(user_id)
        render json: { online: online }
      end
    end
  end
end





