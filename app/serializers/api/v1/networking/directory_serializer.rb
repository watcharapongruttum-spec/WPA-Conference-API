# app/serializers/api/v1/networking/directory_serializer.rb
require "cgi"

module Api
  module V1
    module Networking
      class DirectorySerializer < ActiveModel::Serializer
        attributes :id, :name, :title, :company_name, :avatar_url, :country_code, :is_connected

        def company_name
          object.company&.name || "N/A"
        end

        def country_code
          object.company&.country || "N/A"
        end

        # ✅ แก้แล้ว
        def avatar_url
          object.avatar_url
        end

        def is_connected
          # ✅ FIX: เช็ค connection จริงๆ ผ่าน scope (current_delegate)
          return false unless scope

          ConnectionRequest.where(status: :accepted).exists?(
            [
              "(requester_id = :me AND target_id = :other) OR (requester_id = :other AND target_id = :me)",
              { me: scope.id, other: object.id }
            ]
          )
        end
      end
    end
  end
end
