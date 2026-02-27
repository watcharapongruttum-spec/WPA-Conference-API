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
                 :connection_status

      # ---------------- COMPANY ----------------
      def company_name
        object.company&.name || "N/A"
      end

      def country_code
        object.company&.country || "N/A"
      end

      # ---------------- AVATAR ----------------
      # ✅ แก้แล้ว — เรียก model method
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

        Connection.where(
          "(requester_id = :me AND target_id = :other)
      OR
      (requester_id = :other AND target_id = :me)",
          me: me.id,
          other: object.id
        ).where(status: "accepted").exists? # ← เพิ่ม .where(status: 'accepted')
      end

      def connection_status
        object.connection_status_with(scope)
      end
    end
  end
end
