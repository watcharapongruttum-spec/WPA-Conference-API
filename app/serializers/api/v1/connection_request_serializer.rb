module Api
  module V1
    class ConnectionRequestSerializer < ActiveModel::Serializer
      attributes :id,
                 :status,
                 :requester_id,
                 :target_id,
                 :created_at,
                 :updated_at,
                 :accepted_at,
                 :requester,
                 :target

      # ============================
      # BASIC IDS
      # ============================

      def requester_id
        object.requester_id
      end

      def target_id
        object.target_id
      end

      # ============================
      # ACCEPTED AT (only if accepted)
      # ============================

      def accepted_at
        object.accepted? ? object.updated_at : nil
      end

      # ============================
      # REQUESTER OBJECT
      # ============================

      def requester
        return nil unless object.requester

        {
          id: object.requester.id,
          name: object.requester.name,
          title: object.requester.title,
          company_name: object.requester.company&.name,
          avatar_url: Api::V1::DelegateSerializer
                        .new(object.requester)
                        .avatar_url
        }
      end

      # ============================
      # TARGET OBJECT
      # ============================

      def target
        return nil unless object.target

        {
          id: object.target.id,
          name: object.target.name,
          title: object.target.title,
          company_name: object.target.company&.name,
          avatar_url: Api::V1::DelegateSerializer
                        .new(object.target)
                        .avatar_url
        }
      end
    end
  end
end
