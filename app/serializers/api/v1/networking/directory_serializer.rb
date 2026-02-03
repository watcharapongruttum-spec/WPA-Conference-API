# app/serializers/api/v1/networking/directory_serializer.rb
require 'cgi'

module Api
  module V1
    module Networking
      class DirectorySerializer < ActiveModel::Serializer
        attributes :id, :name, :title, :company_name, :avatar_url, :country_code, :is_connected

        def company_name
          object.company&.name || 'N/A'
        end

        def country_code
          object.company&.country || 'N/A'
        end

        def avatar_url
          # ใช้ fallback avatar เสมอ หลีกเลี่ยง ActiveStorage
          name = object.name.presence || 'Unknown'
          "https://ui-avatars.com/api/?name=#{CGI.escape(name)}&background=0D8ABC&color=fff"
        end

        def is_connected
          # TODO: Implement actual connection check
          false
        end
      end
    end
  end
end