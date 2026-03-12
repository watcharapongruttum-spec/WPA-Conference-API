# app/serializers/api/v1/delegate_serializer.rb
require "cgi"

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
                 :first_login,
                 :is_connected,
                 :connection_status,
                 :connection_request_id

      # ---------------- COMPANY ----------------
      def company_name
        object.company&.name || "N/A"
      end

      def connection_request_id
        object.connection_request_id_with(scope)
      end

      def country_code
        object.company&.country || "N/A"
      end

      # ---------------- AVATAR ----------------
      def avatar_url
        object.avatar_url
      end

      # ---------------- LOGIN ----------------
      def first_login
        object.first_login? || false
      end

      # ---------------- CONNECTION ----------------
      def is_connected
        me = scope
        return false if me.nil?
        return false if me.id == object.id
        connected_ids_for(me).include?(object.id)
      end

      def connection_status
        object.connection_status_with(scope)
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
