module Api
  module V1
    class MessagesController < ApplicationController
      before_action :set_message, only: [:update, :destroy, :mark_as_read]


      def rooms
        me = current_delegate.id

        partner_ids = ChatMessage
          .not_deleted
          .where("sender_id = :me OR recipient_id = :me", me: me)
          .pluck(:sender_id, :recipient_id)
          .flatten.uniq.reject { |id| id == me }

        return render json: [] if partner_ids.empty?

        delegates = Delegate
          .where(id: partner_ids)
          .includes(:company)
          .index_by(&:id)

        # ✅ PostgreSQL DISTINCT ON — last message per partner ใน query เดียว
        last_messages = ChatMessage
          .not_deleted
          .select(
            Arel.sql(
              "DISTINCT ON (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id)) " \
              "id, content, created_at, sender_id, recipient_id"
            )
          )
          .where(
            "(sender_id = :me AND recipient_id IN (:ids)) OR (sender_id IN (:ids) AND recipient_id = :me)",
            me: me, ids: partner_ids
          )
          .order(
            Arel.sql("LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id), created_at DESC")
          )
          .index_by { |m| m.sender_id == me ? m.recipient_id : m.sender_id }

        unread_counts = ChatMessage
          .not_deleted
          .where(recipient_id: me, read_at: nil)
          .where(sender_id: partner_ids)
          .group(:sender_id)
          .count

        rooms = partner_ids.map do |partner_id|
          partner = delegates[partner_id]
          next unless partner

          last_msg = last_messages[partner_id]

          {
            id: partner_id,
            room_kind: "direct",
            delegate: {
              id: partner.id,
              name: partner.name,
              title: partner.title,
              # avatar_url: partner.avatar&.url
              # avatar_url: s.avatar_url
              avatar_url: partner.avatar_url
            },
            last_message: last_msg&.content,
            last_message_at: last_msg&.created_at,
            unread_count: unread_counts[partner_id] || 0
          }
        end.compact

        rooms.sort_by! { |r| r[:last_message_at] || Time.at(0) }
        rooms.reverse!

        render json: rooms
      end



      # ================= MARK AS READ (single) =================
      def mark_as_read
        message = ChatMessage.find(params[:id])

        # เฉพาะ recipient เท่านั้นที่ mark ได้
        return render json: { error: "Forbidden" }, status: :forbidden \
          unless message.recipient_id == current_delegate.id

        return render json: { error: "Already read" }, status: :ok \
          if message.read_at.present?

        message.update!(read_at: Time.current)

        render json: { success: true, read_at: message.read_at }
      end





      # ================= INDEX =================
      def index
        @messages = ChatMessage
                      .not_deleted
                      .where("sender_id = :me OR recipient_id = :me", me: current_delegate.id)
                      .includes(
                        sender: :company,
                        recipient: :company
                      )
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
                      .includes(
                        sender: :company,
                        recipient: :company
                      )
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

        content = message_params[:content].to_s.strip

        if content.blank?
          return render json: {
            error: "Validation failed",
            details: { content: ["cannot be blank"] }
          }, status: :unprocessable_entity
        end

        if content.length > 2000
          return render json: {
            error: "Validation failed",
            details: { content: ["must be between 1 and 2000 characters"] }
          }, status: :unprocessable_entity
        end

        message = nil

        ActiveRecord::Base.transaction do
          message = Chat::SendMessageService.call(
            sender: current_delegate,
            recipient_id: message_params[:recipient_id],
            content: content
          )
        end

        # ✅ trigger ActionCable + FCM (เฉพาะตอน recipient offline)
        Notification::CreateService.call(message)

        AuditLogger.message_created(message, request) if defined?(AuditLogger)

        message = ChatMessage
                    .includes(sender: :company, recipient: :company)
                    .find(message.id)

        render json: message,
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
        sender_id = params[:sender_id].to_s.strip

        # 🔥 ป้องกัน null / empty / non-integer
        unless sender_id.present? && sender_id =~ /\A\d+\z/
          return render json: { unread_count: 0 }
        end

        count = ChatMessage
                  .where(
                    sender_id: sender_id.to_i,
                    recipient_id: current_delegate.id,
                    read_at: nil
                  )
                  .count

        render json: { unread_count: count.to_i }
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
