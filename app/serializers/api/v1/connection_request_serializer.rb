module Api
  module V1
    class ConnectionRequestSerializer < ActiveModel::Serializer
      attributes :id, :status, :created_at, :accepted_at, :requester, :target
      
      def requester
        {
          id: object.requester.id,
          name: object.requester.name,
          title: object.requester.title,
          company_name: object.requester.company&.name,
          avatar_url: Api::V1::DelegateSerializer.new(object.requester).avatar_url
        }
      end
      
      def target
        {
          id: object.target.id,
          name: object.target.name,
          title: object.target.title,
          company_name: object.target.company&.name,
          avatar_url: Api::V1::DelegateSerializer.new(object.target).avatar_url
        }
      end
    end
  end
end
