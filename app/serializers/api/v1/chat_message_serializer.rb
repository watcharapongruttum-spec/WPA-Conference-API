module Api
  module V1
    class ChatMessageSerializer < ActiveModel::Serializer
      attributes :id, :content, :read_at, :created_at, :sender, :recipient
      
      def sender
        {
          id: object.sender.id,
          name: object.sender.name,
          title: object.sender.title,
          company_name: object.sender.company&.name,
          avatar_url: Api::V1::DelegateSerializer.new(object.sender).avatar_url
        }
      end
      
      def recipient
        {
          id: object.recipient.id,
          name: object.recipient.name,
          title: object.recipient.title,
          company_name: object.recipient.company&.name,
          avatar_url: Api::V1::DelegateSerializer.new(object.recipient).avatar_url
        }
      end
    end
  end
end
