module Api
  module V1
    class ChatMessageSerializer < ActiveModel::Serializer
      attributes :id, :content, :read_at, :created_at, :sender, :recipient
      attribute :edited_at
      attribute :deleted_at
      attribute :is_deleted




    def is_deleted
      object.deleted_at.present?
    end








      

      def sender
        s = object.sender
        return nil unless s

        {
          id: s.id,
          name: s.name,
          title: s.title,
          company_name: s.company&.name,
          # avatar_url: Api::V1::DelegateSerializer.new(s).avatar_url
          avatar_url: s.avatar&.url

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
          avatar_url: Api::V1::DelegateSerializer.new(r).avatar_url
        }
      end
    end
  end
end
