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
          return false unless scope

          connected_ids_for(scope).include?(object.id)
        end

        private

        def connected_ids_for(delegate)
          delegate.instance_variable_get(:@_connected_ids) || begin
            ids = Connection
                    .where(status: "accepted")
                    .where("requester_id = :id OR target_id = :id", id: delegate.id)
                    .pluck(:requester_id, :target_id)
                    .flatten
                    .reject { |id| id == delegate.id }
                    .to_set
            delegate.instance_variable_set(:@_connected_ids, ids)
            ids
          end
        end
      end
    end
  end
end
