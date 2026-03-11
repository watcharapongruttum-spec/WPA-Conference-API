module Api
  module V1
    class MessagesController < ApplicationController
      before_action :set_message, only: %i[update destroy mark_as_read]

      def rooms
        me = current_delegate.id

        partner_ids = ChatMessage
                      .where(
                        "(sender_id = :me AND deleted_for_sender_at IS NULL) OR " \
                        "(recipient_id = :me AND deleted_for_recipient_at IS NULL)",
                        me: me
                      )
                      .where.not(recipient_id: nil)
                      .where(chat_room_id: nil)
                      .pluck(:sender_id, :recipient_id)
                      .flatten
                      .compact
                      .uniq
                      .reject { |id| id == me }

        return render json: [] if partner_ids.empty?

        delegates = Delegate
                    .where(id: partner_ids)
                    .includes(:company)
                    .index_by(&:id)

        last_messages = ChatMessage
                        .where(
                          "(sender_id = :me    AND deleted_for_sender_at    IS NULL) OR " \
                          "(recipient_id = :me AND deleted_for_recipient_at IS NULL)",
                          me: me
                        )
                        .where.not(recipient_id: nil)
                        .where(chat_room_id: nil)
                        .select(
                          Arel.sql(
                            "DISTINCT ON (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id)) " \
                            "id, content, message_type, created_at, sender_id, recipient_id"
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
                        .where(recipient_id: me, read_at: nil, deleted_at: nil)
                        .where(deleted_for_recipient_at: nil)
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
              avatar_url: partner.avatar_url
            },
            last_message:      last_msg&.content_preview,
            last_message_type: last_msg&.message_type,
            last_message_at:   last_msg&.created_at,
            unread_count:      unread_counts[partner_id] || 0
          }
        end.compact

        rooms.sort_by! { |r| r[:last_message_at] || Time.at(0) }
        rooms.reverse!

        render json: rooms
      end

      # ================= MARK AS READ (single) =================
      def mark_as_read
        return render json: { error: "Forbidden" }, status: :forbidden \
          unless @message.recipient_id == current_delegate.id

        return render json: { success: true, read_at: TimeFormatter.format(@message.read_at) }, status: :ok \
          if @message.read_at.present?

        # ✅ ใช้ ReadService — sync ทั้ง read_at และ MessageRead และ broadcast WS
        Chat::ReadService.mark_one(@message)

        Rails.cache.delete("dashboard:#{current_delegate.id}:v1")

        render json: { success: true, read_at: TimeFormatter.format(@message.reload.read_at) }
      end

      # ================= INDEX =================
      def index
        @messages = ChatMessage
                    .visible_to(current_delegate.id)
                    .where(chat_room_id: nil)
                    .where.not(recipient_id: nil)
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
                    .where(
                      "(sender_id = :me AND recipient_id = :other) OR
                       (sender_id = :other AND recipient_id = :me)",
                      me: current_delegate.id,
                      other: other_id
                    )
                    .visible_to(current_delegate.id)   # ← per-user filter
                    .where(chat_room_id: nil)
                    .includes(
                      sender: :company,
                      recipient: :company
                    )
                    .reorder(created_at: :desc, id: :desc)
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
        recipient_id = message_params[:recipient_id]
        return render json: { error: "recipient_id required" }, status: :unprocessable_entity unless recipient_id

        recipient = Delegate.find_by(id: recipient_id)
        return render json: { error: "Recipient not found" }, status: :not_found unless recipient

        # ================= IMAGE =================
        if params.dig(:message, :image).present?
          message = nil

          ActiveRecord::Base.transaction do
            message = ChatMessage.create!(
              sender:       current_delegate,
              recipient_id: recipient_id,
              content:      "",
              message_type: "image"
            )

            Chat::ImageService.attach(
              message:  message,
              data_uri: params[:message][:image]
            )
          end

        else
          # ================= TEXT =================
          content = message_params[:content].to_s.strip

          return render json: {
            error: "Validation failed",
            details: { content: ["cannot be blank"] }
          }, status: :unprocessable_entity if content.blank?

          return render json: {
            error: "Validation failed",
            details: { content: ["must be between 1 and 2000 characters"] }
          }, status: :unprocessable_entity if content.length > 2000

          message = Chat::SendMessageService.call(
            sender:       current_delegate,
            recipient_id: recipient_id,
            content:      content
          )
        end

        # ================= COMMON PART =================
        Notification::CreateService.call(message)
        AuditLogger.message_created(message, request) if defined?(AuditLogger)

        message = ChatMessage
                    .includes(sender: :company, recipient: :company)
                    .find(message.id)

        payload = {
          type: "new_message",
          message: Api::V1::ChatMessageSerializer
                    .new(message)
                    .serializable_hash
        }

        ChatChannel.broadcast_to(message.recipient, payload)
        ChatChannel.broadcast_to(message.sender,    payload)

        render json: message,
              serializer: Api::V1::ChatMessageSerializer,
              status: :created

      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_entity

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

        return render json: { error: "Content cannot be blank" }, status: :unprocessable_entity if update_params[:content].blank?

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

        return render json: { unread_count: 0 } unless sender_id.present? && sender_id =~ /\A\d+\z/

        count = ChatMessage
                .where(
                  sender_id: sender_id.to_i,
                  recipient_id: current_delegate.id,
                  read_at: nil,
                  deleted_at: nil,
                  deleted_for_recipient_at: nil   # ← ไม่นับที่ลบแล้ว
                )
                .count

        render json: { unread_count: count.to_i }
      end

      def online_status
        online = Chat::PresenceService.online?(params[:user_id])
        render json: { online: online }
      end

      # ================= CLEAR CONVERSATION (per-user) =================
      def clear_conversation
        other_id = params[:delegate_id].to_i
        me       = current_delegate.id

        return render json: { error: "Cannot clear conversation with yourself" },
                      status: :unprocessable_entity if other_id == me

        return render json: { error: "Delegate not found" },
                      status: :not_found unless Delegate.exists?(other_id)

        now = Time.current

        # Messages ที่เราเป็น sender → set deleted_for_sender_at
        count_as_sender = ChatMessage
          .where(sender_id: me, recipient_id: other_id)
          .where(deleted_for_sender_at: nil)
          .update_all(deleted_for_sender_at: now)

        # Messages ที่เราเป็น recipient → set deleted_for_recipient_at
        count_as_recipient = ChatMessage
          .where(sender_id: other_id, recipient_id: me)
          .where(deleted_for_recipient_at: nil)
          .update_all(deleted_for_recipient_at: now)

        render json: {
          success: true,
          deleted_count: count_as_sender + count_as_recipient
        }
      end

      private

      def set_message
        @message = ChatMessage.find(params[:id])
      end

      def message_params
        params.require(:message).permit(:recipient_id, :content, :image)
      end

      def update_params
        params.require(:message).permit(:content)
      end
    end
  end
end