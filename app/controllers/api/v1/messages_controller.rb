module Api
  module V1
    class MessagesController < ApplicationController
      before_action :set_message, only: [:update, :destroy]

      def rooms
        me = current_delegate.id

        messages = ChatMessage
                    .not_deleted
                    .where("sender_id = :me OR recipient_id = :me", me: me)

        # หา id ของคู่สนทนา
        partner_ids = messages.pluck(:sender_id, :recipient_id)
                              .flatten
                              .uniq
                              .reject { |id| id == me }

        rooms = partner_ids.map do |partner_id|
          conversation = ChatMessage
                          .not_deleted
                          .where(
                            "(sender_id = :me AND recipient_id = :other)
                              OR
                              (sender_id = :other AND recipient_id = :me)",
                            me: me,
                            other: partner_id
                          )

          last_message = conversation.order(created_at: :desc).first
          unread_count = conversation.where(
                          recipient_id: me,
                          read_at: nil
                        ).count

          {
            partner: Delegate.find(partner_id),
            last_message: last_message,
            unread_count: unread_count
          }
        end

        # sort ล่าสุดก่อน
        rooms.sort_by! { |r| r[:last_message]&.created_at || Time.at(0) }
        rooms.reverse!

        render json: rooms
      end



      # ================= INDEX =================
      def index
        @messages = ChatMessage
          .not_deleted
          .where("sender_id = :me OR recipient_id = :me", me: current_delegate.id)
          .includes(:sender, :recipient)
          .order(created_at: :desc)
          .page(params[:page] || 1)
          .per([params[:per].to_i, 100].min)

        render json: @messages, each_serializer: Api::V1::ChatMessageSerializer
      end

      # ================= CONVERSATION =================
      def conversation
        other_id = params[:delegate_id]
        page = (params[:page] || 1).to_i
        per  = [(params[:per] || 50).to_i, 100].min

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

      # ================= CREATE =================
      def create
        return render json: { error: "recipient_id required" }, status: :unprocessable_entity unless message_params[:recipient_id]

        if message_params[:content].blank?
          return render json: {
            error: "Validation failed",
            details: { content: ["cannot be blank"] }
          }, status: :unprocessable_entity
        end

        if message_params[:content].length > 2000
          return render json: {
            error: "Validation failed",
            details: { content: ["must be between 1 and 2000 characters"] }
          }, status: :unprocessable_entity
        end

        @message = Chat::SendMessageService.call(
          sender: current_delegate,
          recipient_id: message_params[:recipient_id],
          content: message_params[:content]
        )

        AuditLogger.message_created(@message, request) if defined?(AuditLogger)

        render json: @message,
               serializer: Api::V1::ChatMessageSerializer,
               status: :created

      rescue ActiveRecord::RecordInvalid => e
        render json: {
          error: "Validation failed",
          details: e.record.errors.full_messages
        }, status: :unprocessable_entity
      end

      # ================= UPDATE =================
      def update
        return render json: { error: "Forbidden" }, status: :forbidden unless @message.sender == current_delegate
        return render json: { error: "Message deleted" }, status: :unprocessable_entity if @message.deleted?

        if update_params[:content].blank?
          return render json: { error: "Content cannot be blank" }, status: :unprocessable_entity
        end

        old_content = @message.content

        Chat::UpdateMessageService.call(
          message: @message,
          content: update_params[:content]
        )

        AuditLogger.message_updated(
          @message,
          { old_content: old_content, new_content: update_params[:content] },
          request
        )

        render json: { success: true }
      end

      # ================= DESTROY =================
      def destroy
        return render json: { error: "Forbidden" }, status: :forbidden unless @message.sender == current_delegate
        return render json: { error: "Already deleted" }, status: :unprocessable_entity if @message.deleted?

        Chat::DeleteMessageService.call(message: @message)
        AuditLogger.message_deleted(@message, request)

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
        online = Chat::PresenceService.online?(params[:user_id])
        render json: { online: online }
      end

      private

      def set_message
        @message = ChatMessage.find(params[:id])
      end

      # ⭐ Strong params สำหรับ create
      def message_params
        params.require(:message).permit(:recipient_id, :content)
      end

      # ⭐ Strong params สำหรับ update
      def update_params
        params.require(:message).permit(:content)
      end
    end
  end
end
