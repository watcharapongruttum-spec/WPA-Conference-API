# app/serializers/api/v1/schedule_detail_serializer.rb
module Api
  module V1
    class ScheduleDetailSerializer < ActiveModel::Serializer
      attributes :id, :title, :start_at, :end_at, :table_number, :type, :booker, :target, :conference_date

      def title
        "Meeting at #{object.table_number.presence || 'Table'}"
      end

      def type
        "1-on-1 Meeting"
      end

      def booker
        if object.booker
          {
            id: object.booker.id,
            name: object.booker.name,
            title: object.booker.title,
            company: object.booker.company&.name || "N/A",
            avatar_url: begin
              Api::V1::DelegateSerializer.new(object.booker).avatar_url
            rescue StandardError
              "https://ui-avatars.com/api/?name=#{CGI.escape(object.booker.name)}&background=0D8ABC&color=fff"
            end
          }
        else
          {
            id: nil,
            name: "Unknown",
            title: "N/A",
            company: "N/A",
            avatar_url: "https://ui-avatars.com/api/?name=Unknown&background=0D8ABC&color=fff"
          }
        end
      end

      def target
        if object.target
          {
            id: object.target.id,
            name: object.target.name,
            title: object.target.title,
            company: object.target.company&.name || "N/A",
            avatar_url: begin
              Api::V1::DelegateSerializer.new(object.target).avatar_url
            rescue StandardError
              "https://ui-avatars.com/api/?name=#{CGI.escape(object.target.name)}&background=0D8ABC&color=fff"
            end
          }
        else
          {
            id: nil,
            name: "Unknown",
            title: "N/A",
            company: "N/A",
            avatar_url: "https://ui-avatars.com/api/?name=Unknown&background=0D8ABC&color=fff"
          }
        end
      end

      def conference_date
        if object.conference_date
          {
            id: object.conference_date.id,
            date: object.conference_date.on_date,
            conference_name: object.conference_date.conference&.name || "N/A"
          }
        else
          {
            id: nil,
            date: nil,
            conference_name: "N/A"
          }
        end
      end
    end
  end
end
