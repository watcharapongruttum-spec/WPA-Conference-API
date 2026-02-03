# app/serializers/api/v1/delegate_serializer.rb
require 'cgi'

module Api
  module V1
    class DelegateSerializer < ActiveModel::Serializer
      attributes :id,
                 :name,
                 :title,
                 :email,
                 :company_name,
                 :avatar_url,
                 :country_code,
                 :team_id,
                 :first_login

      def company_name
        object.company&.name || 'N/A'
      end

      def country_code
        object.company&.country || 'N/A'
      end

      # ใช้ fallback avatar เสมอ หลีกเลี่ยง ActiveStorage ทั้งหมด
      def avatar_url
        name = object.name.presence || 'Unknown'
        "https://ui-avatars.com/api/?name=#{CGI.escape(name)}&background=0D8ABC&color=fff"
      end

      def first_login
        object.first_login? || false
      end
    end
  end
end
