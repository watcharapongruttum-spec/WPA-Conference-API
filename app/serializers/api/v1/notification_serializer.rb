# app/serializers/api/v1/notification_serializer.rb
module Api
  module V1
    class NotificationSerializer < ActiveModel::Serializer
      # 🔴 FIX 1: เปลี่ยน :unread? → :is_unread
      # AMS บางเวอร์ชัน parse method name ที่มี "?" ไม่ได้ → crash หรือ JSON key = "unread?"
      attributes :id, :type, :read_at, :created_at, :is_unread, :notifiable

      def type
        object.notification_type
      end

      # 🔴 FIX 1 (ต่อ): method แทน :unread?
      def is_unread
        object.read_at.nil?
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
          type:      'connection_request',
          id:        connection.id,
          requester: delegate_json(connection.requester),
          target:    delegate_json(connection.target),
          status:    connection.status
        }
      end

      def message_json(message)
        {
          type:    'message',
          id:      message.id,
          sender:  delegate_json(message.sender),
          content: message.content.to_s.truncate(50)
        }
      end

      def delegate_json(delegate)
        return nil unless delegate

        # 🔴 FIX 4: avatar fallback — Delegate#avatar_url คืน nil ถ้าไม่มี attachment
        # ทุก serializer อื่นใช้ ui-avatars แต่ตัวนี้ลืม → client ได้ null
        avatar = delegate.avatar_url.presence ||
                 "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name.presence || 'Unknown')}&background=0D8ABC&color=fff"

        {
          id:         delegate.id,
          name:       delegate.name,
          avatar_url: avatar
        }
      end
    end
  end
end