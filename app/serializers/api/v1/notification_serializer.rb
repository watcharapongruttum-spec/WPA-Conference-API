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
        when "new_message"
          message_json(item)
        when "new_group_message"
          group_message_json(item) # ✅ แยก case
        when "connection_request", "connection_accepted", "connection_rejected"
          connection_json(item)
        when "admin_announce"
          announce_json(item)
        end
      end

      private

      def message_json(message)
        {
          type: "message",
          id: message.id,
          sender: delegate_json(message.sender),
          content: message.content.to_s.truncate(50)
        }
      end

      def group_message_json(message)
        {
          type: "group_message",
          id: message.id,
          room_id: message.chat_room_id, # ✅ frontend navigate ได้
          room_title: message.chat_room&.title,    # ✅ แสดงชื่อห้อง
          sender: delegate_json(message.sender),
          content: message.content.to_s.truncate(50)
        }
      end

      def connection_json(connection)
        {
          type: "connection_request",
          connection_request_id: connection.id,    # ✅ ใช้ accept/reject
          id: connection.id,
          requester: delegate_json(connection.requester),
          target: delegate_json(connection.target),
          status: connection.status
        }
      end

      def announce_json(announcement)
        {
          type: "admin_announce",
          id: announcement&.id,
          content: announcement&.content&.truncate(200)
        }
      end

      def delegate_json(delegate)
        return nil unless delegate

        {
          id: delegate.id,
          name: delegate.name,
          avatar_url: delegate.avatar_url
        }
      end
    end
  end
end
