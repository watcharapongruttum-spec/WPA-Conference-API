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




      def my_schedule
        result = Schedule.build_my_schedule(
          delegate: current_delegate,
          params: params
        )

        return render json: { error: result[:error] }, status: :not_found if result[:error]

        render_timeline(result, current_delegate)
      end

      def schedule_others
        result = Schedule.build_schedule_others(
          viewer: current_delegate,
          params: params
        )

        return render json: { error: result[:error] }, status: :not_found if result[:error]

        render_timeline(result, result[:user], include_user: true)
      end

      private

      def render_timeline(result, scope_user, include_user: false)
        timeline = result[:schedules].map do |item|
          if item[:type] == "event"
            item
          else
            schedule = item[:serializer]

            data = ActiveModelSerializers::SerializableResource.new(
              schedule,
              serializer: Api::V1::ScheduleSerializer,
              scope: scope_user
            ).as_json.except(:delegate)

            meeting_type = schedule.table_number.nil? ? "nomeeting" : "meeting"

            data.merge(
              type: meeting_type,
              team_delegates: (schedule.team&.delegates || []).map do |d|
                {
                  id: d.id,
                  name: d.name,
                  company: d.company&.name
                }
              end
            )
          end
        end

        response = {
          available_years: result[:years] || [],
          year: result[:year],
          available_dates: result[:available_dates] || [],
          date: result[:selected_date],
          schedules: timeline
        }

        if include_user
          response[:user] = Api::V1::DelegateSerializer.new(result[:user])
        end

        render json: response
      end
    end
  end
end
