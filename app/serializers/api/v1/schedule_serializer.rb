# app/serializers/api/v1/schedule_serializer.rb
module Api
  module V1
    class ScheduleSerializer < ActiveModel::Serializer
      attributes :id, :title, :start_at, :end_at, :table_number, :type, :delegate
      
      def title
        "Meeting at #{object.table_number.presence || 'Table'}"
      end
      
      def type
        "1-on-1 Meeting"
      end
      
      def delegate
        # หา delegate อีกคนที่ไม่ใช่ตัวเอง (ถ้ามี)
        other_delegate = if scope && object.booker_id == scope.id
          object.target
        else
          object.booker
        end
        
        # ตรวจสอบ nil ก่อนใช้งาน
        if other_delegate&.persisted?
          {
            id: other_delegate.id,
            name: other_delegate.name.presence || 'Unknown',
            company: other_delegate.company&.name.presence || 'N/A',
            avatar_url: begin
              Api::V1::DelegateSerializer.new(other_delegate).avatar_url
            rescue => e
              "https://ui-avatars.com/api/?name=#{CGI.escape(other_delegate.name)}&background=0D8ABC&color=fff"
            end
          }
        else
          {
            id: nil,
            name: 'Unknown',
            company: 'N/A',
            avatar_url: 'https://ui-avatars.com/api/?name=Unknown&background=0D8ABC&color=fff'
          }
        end
      end
      
      def current_user
        scope
      end
    end
  end
end