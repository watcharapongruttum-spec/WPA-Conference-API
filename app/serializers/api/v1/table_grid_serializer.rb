# app/serializers/api/v1/table_grid_serializer.rb
module Api
  module V1
    class TableGridSerializer < ActiveModel::Serializer
      attributes :id, :table_number, :status, :occupancy, :capacity

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
    end
  end
end
