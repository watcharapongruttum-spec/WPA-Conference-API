module Api
  module V1
    class SchedulesController < ApplicationController
      # ===============================
      # INDEX
      # ===============================
      def index
        result = Schedule.build_index(
          delegate: current_delegate,
          params: index_params
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
        result = Schedule.build_my_schedule(
          delegate: current_delegate,
          params: timeline_params
        )

        return render json: { error: result[:error] }, status: :not_found if result[:error]

        render_timeline(result, current_delegate)
      end

      # ===============================
      # SCHEDULE OTHERS
      # ===============================
      def schedule_others
        result = Schedule.build_schedule_others(
          viewer: current_delegate,
          params: timeline_params
        )

        return render json: { error: result[:error] }, status: :not_found if result[:error]

        render_timeline(result, result[:user], include_user: true)
      end

      private

      # ===============================
      # STRONG PARAMS
      # ===============================

      # สำหรับสร้าง schedule
      def schedule_params
        params.require(:schedule).permit(
          :start_time,
          :end_time,
          :date,
          :table_number,
          :team_id,
          :location,
          :note
        )
      end

      # สำหรับ index (pagination / filter)
      def index_params
        params.permit(
          :page,
          :per_page,
          :year,
          :date,
          :team_id,
          :delegate_id
        )
      end

      # สำหรับ my_schedule / schedule_others
      def timeline_params
        params.permit(
          :year,
          :date,
          :delegate_id
        )
      end

      # ===============================
      # RENDER TIMELINE (เหมือนเดิม 100%)
      # ===============================
      def render_timeline(result, scope_user, include_user: false)
        timeline = result[:schedules].map do |item|
          if item[:type] == "event" || item[:type] == "nomeeting"
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
              # team_delegates: (schedule.team&.delegates || []).map do |d|
              team_delegates: schedule.team_delegates.map do |d|
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

        response[:user] = Api::V1::DelegateSerializer.new(result[:user]) if include_user

        render json: response
      end
    end
  end
end
