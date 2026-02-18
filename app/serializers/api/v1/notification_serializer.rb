module Api
  module V1
    class NotificationSerializer < ActiveModel::Serializer
      attributes :id, :type, :read_at, :created_at, :unread?, :notifiable

      def type
        object.notification_type
      end

      def notifiable
        item = object.notifiable
        return nil unless item

        case object.notifiable_type
        when 'ConnectionRequest'
          connection_json(item)
        when 'ChatMessage', 'Message'
          message_json(item)
        end
      end

      private

      def connection_json(connection)
        {
          type: 'connection_request',
          id: connection.id,
          requester: delegate_json(connection.requester),
          target: delegate_json(connection.target),
          status: connection.status
        }
      end

      def message_json(message)
        {
          type: 'message',
          id: message.id,
          sender: delegate_json(message.sender),
          content: message.content.to_s.truncate(50)
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
