module Api
  module V1
    class ChatMessageSerializer < ActiveModel::Serializer
      attributes :id, :content, :is_deleted, :sender, :recipient

      def is_deleted
        object.deleted_at.present?
      end

      # ✅ Override timestamps → Bangkok
      def created_at
        object.created_at&.in_time_zone('Asia/Bangkok')&.iso8601
      end

      def read_at
        object.read_at&.in_time_zone('Asia/Bangkok')&.iso8601
      end

      def edited_at
        object.edited_at&.in_time_zone('Asia/Bangkok')&.iso8601
      end

      def deleted_at
        object.deleted_at&.in_time_zone('Asia/Bangkok')&.iso8601
      end

      attribute :created_at
      attribute :read_at
      attribute :edited_at
      attribute :deleted_at

      def sender
        s = object.sender
        return nil unless s
        {
          id: s.id,
          name: s.name,
          title: s.title,
          company_name: s.company&.name,
          avatar_url: s.avatar_url
        }
      end

      def recipient
        r = object.recipient
        return nil unless r
        {
          id: r.id,
          name: r.name,
          title: r.title,
          company_name: r.company&.name,
          avatar_url: r.avatar_url
        }
      end
    end
  end
end