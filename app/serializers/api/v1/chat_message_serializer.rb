module Api
  module V1
    class ChatMessageSerializer < ActiveModel::Serializer
      attributes :id, :content, :is_deleted, :sender, :recipient

      def is_deleted
        object.deleted_at.present?
      end

      attribute :created_at
      attribute :read_at
      attribute :edited_at
      attribute :deleted_at

      def created_at  = TimeFormatter.format(object.created_at)
      def read_at     = TimeFormatter.format(object.read_at)
      def edited_at   = TimeFormatter.format(object.edited_at)
      def deleted_at  = TimeFormatter.format(object.deleted_at)

      def sender
        s = object.sender
        return nil unless s
        { id: s.id, name: s.name, title: s.title,
          company_name: s.company&.name, avatar_url: s.avatar_url }
      end

      def recipient
        r = object.recipient
        return nil unless r
        { id: r.id, name: r.name, title: r.title,
          company_name: r.company&.name, avatar_url: r.avatar_url }
      end
    end
  end
end