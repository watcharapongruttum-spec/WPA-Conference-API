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

        @message = Chat::SendMessageService.call(
          sender: current_delegate,
          recipient_id: recipient_id,
          content: params[:content]
        )

        render json: @message,
              serializer: Api::V1::ChatMessageSerializer,
              status: :created
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
        Chat::ReadService.read_all(current_delegate)
        render json: { message: "All messages marked as read" }
      end



      # ================= UPDATE =================
      def update
        message = ChatMessage.find(params[:id])

        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Message deleted" }, status: 422 if message.deleted?
        return render json: { error: "Content cannot be blank" }, status: 422 if params[:content].blank?

        Chat::UpdateMessageService.call(
          message: message,
          content: params[:content]
        )

        render json: { success: true }
      end


      # ================= DESTROY =================
      def destroy
        message = ChatMessage.find(params[:id])

        return render json: { error: "Forbidden" }, status: :forbidden unless message.sender == current_delegate
        return render json: { error: "Already deleted" }, status: 422 if message.deleted?

        Chat::DeleteMessageService.call(message: message)

        render json: { success: true }
      end



      def online_status
        user_id = params[:user_id]
        online = Chat::PresenceService.online?(user_id)
        render json: { online: online }
      end




      private
    end
  end
end
