# app/serializers/api/v1/table_serializer.rb
module Api
  module V1
    class TableSerializer < ActiveModel::Serializer
      attributes :id, :table_number, :status, :occupancy, :delegates

      def status
        if occupancy.zero?
          "empty"
        elsif occupancy >= capacity
          "full"
        else
          "partial"
        end
      end

      def occupancy
        object.teams.flat_map(&:delegates).count
      end

      def capacity
        4
      end

      def delegates
        object.teams.flat_map(&:delegates).map do |delegate|
          {
            id: delegate.id,
            name: delegate.name,
            company: delegate.company&.name || "N/A",
            avatar_url: begin
              Api::V1::DelegateSerializer.new(delegate).avatar_url
            rescue StandardError
              "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff"
            end,
            title: delegate.title
          }
        end
      end
    end
  end
end
