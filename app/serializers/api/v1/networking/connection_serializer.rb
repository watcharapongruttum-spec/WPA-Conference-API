# app/serializers/api/v1/networking/connection_serializer.rb
require 'cgi'

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

        def delegate_info(delegate)
          return nil unless delegate

          {
            id: delegate.id,
            name: delegate.name || 'Unknown',
            title: delegate.title,
            company_name: delegate.company&.name || 'N/A',
            avatar_url: avatar_url_for(delegate)
          }
        end

        def avatar_url_for(delegate)
          name = delegate.name.presence || 'Unknown'
          "https://ui-avatars.com/api/?name=#{CGI.escape(name)}&background=0D8ABC&color=fff"
        end
      end
    end
  end
end