# app/serializers/api/v1/delegate_detail_serializer.rb
module Api
  module V1
    class DelegateDetailSerializer < ActiveModel::Serializer
      attributes :id, :name, :title, :email, :phone, :company, :avatar_url, :team, :first_conference, :spouse_attending, :need_room
      
      def company
        if object.company
          {
            id: object.company.id,
            name: object.company.name,
            country: object.company.country,
            logo_url: nil # ไม่ใช้ ActiveStorage
          }
        else
          nil
        end
      end
      
      # ✅ แก้แล้ว
      def avatar_url
        object.avatar_url
      end
      
      def team
        if object.team
          {
            id: object.team.id,
            name: object.team.name,
            country_code: object.team.country_code
          }
        else
          nil
        end
      end
    end
  end
end