# app/serializers/api/v1/connection_request_serializer.rb
module Api
  module V1
    class ConnectionRequestSerializer < ActiveModel::Serializer
      attributes :id, :status, :requester_id, :target_id,
                 :created_at, :updated_at, :accepted_at,
                 :requester, :target

      def requester_id = object.requester_id
      def target_id    = object.target_id

      def accepted_at
        object.accepted? ? object.updated_at : nil
      end

      def requester
        DelegatePresenter.basic(object.requester)  # ✅
      end

      def target
        DelegatePresenter.basic(object.target)     # ✅
      end
    end
  end
end