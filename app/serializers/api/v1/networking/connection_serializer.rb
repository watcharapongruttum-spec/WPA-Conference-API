# app/serializers/api/v1/networking/connection_serializer.rb
require "cgi"

module Api
  module V1
    module Networking
      class ConnectionSerializer < ActiveModel::Serializer
        attributes :id, :status, :created_at, :requester, :target

        def requester
          delegate_info(object.requester)
        end

        def target
          delegate_info(object.target)
        end

        private

        # ✅ แก้แล้ว
        def delegate_info(delegate)
          return nil unless delegate

          {
            id: delegate.id,
            name: delegate.name || "Unknown",
            title: delegate.title,
            company_name: delegate.company&.name || "N/A",
            avatar_url: delegate.avatar_url
          }
        end
      end
    end
  end
end
