module Api
  module V1
    class SchedulesController < ApplicationController

      # ===============================
      # INDEX
      # ===============================
      def index
        result = Schedule.build_index(
          delegate: current_delegate,
          params: params
        )

        render json: {
          page: result[:page],
          per_page: result[:per_page],
          total: result[:total],
          schedules: ActiveModelSerializers::SerializableResource.new(
            result[:schedules] || [],
            each_serializer: Api::V1::ScheduleSerializer,
            scope: current_delegate
          )
        }
      end

      # ===============================
      # CREATE
      # ===============================
      def create
        schedule = Schedule.new(schedule_params)

        if schedule.save
          render json: schedule, status: :created
        else
          render json: { errors: schedule.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # ===============================
      # MY SCHEDULE
      # ===============================
      def my_schedule
        return render json: { error: 'Authentication required' }, status: :unauthorized unless current_delegate

        result = Schedule.build_my_schedule(
          delegate: current_delegate,
          params: params
        )

        if result[:error]
          return render json: { error: result[:error] }, status: :not_found
        end


        
        timeline = result[:schedules].map do |item|
          if item[:type] == "event"
            item
          else
            data = ActiveModelSerializers::SerializableResource.new(
              item[:serializer],
              serializer: Api::V1::ScheduleSerializer,
              scope: current_delegate
            ).as_json

            meeting_type =
              data[:table_number].nil? ? "nomeeting" : "meeting"

            data.merge(type: meeting_type)
          end
        end


        render json: {
          available_years: result[:years],
          year: result[:year],
          available_dates: result[:available_dates],
          date: result[:selected_date],
          schedules: timeline
        }


      end

      # ===============================
      # SCHEDULE OTHERS
      # ===============================
      def schedule_others
        return render json: { error: 'Authentication required' }, status: :unauthorized unless current_delegate

        result = Schedule.build_schedule_others(
          viewer: current_delegate,
          params: params
        )

        if result[:error]
          return render json: { error: result[:error] }, status: :not_found
        end

        render json: {
          user: Api::V1::DelegateSerializer.new(result[:user]),
          available_years: result[:years],
          year: result[:year],
          available_dates: result[:available_dates],
          date: result[:selected_date],
          schedules: ActiveModelSerializers::SerializableResource.new(
            result[:schedules],
            each_serializer: Api::V1::ScheduleSerializer,
            scope: result[:user]

          )
        }
      end















      private

      def schedule_params
        params.require(:schedule).permit(
          :conference_date_id,
          :booker_id,
          :target_id,
          :start_at,
          :end_at,
          :table_number,
          :country
        )
      end
    end
  end
end






