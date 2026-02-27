# app/serializers/api/v1/schedule_index_serializer.rb
module Api
  module V1
    class ScheduleIndexSerializer < ActiveModel::Serializer
      attributes :today, :upcoming

      def today
        object[:today].map { |s| Api::V1::ScheduleSerializer.new(s).serializable_hash }
      end

      def upcoming
        object[:upcoming].map { |s| Api::V1::ScheduleSerializer.new(s).serializable_hash }
      end
    end
  end
end
