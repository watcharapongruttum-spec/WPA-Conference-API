module Api
  module V1
    class NotificationSerializer < ActiveModel::Serializer
      attributes :id, :type, :read_at, :created_at, :unread?, :notifiable

      # map notification_type -> type (กันชน STI)
      def type
        object.notification_type
      end

      def notifiable
        item = object.notifiable
        return nil unless item

        case object.notifiable_type
        when 'ConnectionRequest'
          serialize_connection_request(item)

        when 'ChatMessage', 'Message'
          serialize_message(item)

        else
          nil
        end
      end

      private

      # ----------------------------
      # Connection Request
      # ----------------------------
      def serialize_connection_request(connection)
        {
          type: 'connection_request',
          id: connection.id,
          requester: {
            id: connection.requester&.id,
            name: connection.requester&.name,
            avatar_url: avatar_url_for(connection.requester)
          },
          target: {
            id: connection.target&.id,
            name: connection.target&.name,
            avatar_url: avatar_url_for(connection.target)
          },
          status: connection.status
        }
      end

      # ----------------------------
      # Message
      # ----------------------------
      def serialize_message(message)
        {
          type: 'message',
          id: message.id,
          sender: {
            id: message.sender&.id,
            name: message.sender&.name,
            avatar_url: avatar_url_for(message.sender)
          },
          content: message.content.to_s.truncate(50)
        }
      end

      # ----------------------------
      # Helper
      # ----------------------------
      def avatar_url_for(delegate)
        return nil unless delegate
        Api::V1::DelegateSerializer.new(delegate).avatar_url
      end
    end
  end
end




