# app/serializers/api/v1/notification_serializer.rb
module Api
  module V1
    class NotificationSerializer < ActiveModel::Serializer
      attributes :id, :type, :read_at, :created_at, :is_unread, :notifiable

      def type
        object.notification_type
      end

      def is_unread
        object.read_at.nil?
      end

      def notifiable
        item = object.notifiable
        return nil unless item

        case object.notification_type
        when "new_message"       then message_json(item)
        when "new_group_message" then group_message_json(item)
        when "connection_request", "connection_accepted", "connection_rejected"
          connection_json(item)
        when "admin_announce"    then announce_json(item)
        when "leave_reported"    then leave_form_json(item)
        end
      end

      private

      def leave_form_json(leave_form)
        {
          type:        "leave_reported",
          id:          leave_form.id,
          schedule_id: leave_form.schedule_id,
          reporter:    DelegatePresenter.minimal(leave_form.reported_by),
          leave_type:  leave_form.leave_type&.name,
          explanation: leave_form.explanation
        }
      end

      def message_json(message)
        {
          type:    "message",
          id:      message.id,
          sender:  DelegatePresenter.minimal(message.sender),  # ✅
          content: message.content.to_s.truncate(50)
        }
      end

      def group_message_json(message)
        {
          type:        "group_message",
          id:          message.id,
          room_id:     message.chat_room_id,
          room_title:  message.chat_room&.title,
          sender:      DelegatePresenter.minimal(message.sender),  # ✅
          content:     message.content.to_s.truncate(50)
        }
      end

      def connection_json(connection)
        {
          type:                  "connection_request",
          connection_request_id: connection.id,
          id:                    connection.id,
          requester:             DelegatePresenter.minimal(connection.requester),  # ✅
          target:                DelegatePresenter.minimal(connection.target),     # ✅
          status:                connection.status
        }
      end

      def announce_json(announcement)
        {
          type:    "admin_announce",
          id:      announcement&.id,
          content: announcement&.content&.truncate(200)
        }
      end
    end
  end
end