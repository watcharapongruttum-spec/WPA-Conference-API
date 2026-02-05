module Api
  module V1
    class SchedulesController < ApplicationController

      # ===============================
      # INDEX
      # ===============================
      def index
        if current_delegate
          schedules = Schedule
            .where(booker: current_delegate)
            .or(Schedule.where(target: current_delegate))
            .includes(:conference_date, booker: :company, target: :company)
            .order(start_at: :asc)
        else
          schedules = Schedule
            .includes(:conference_date, booker: :company, target: :company)
            .order(start_at: :asc)
            .limit(50)
        end

        render json: schedules,
               each_serializer: Api::V1::ScheduleSerializer,
               scope: current_delegate
      end





      # ===============================
      # MY SCHEDULE
      # ===============================
      def my_schedule
        delegate = current_delegate
        return render json: { error: 'Authentication required' }, status: :unauthorized if delegate.nil?

        # -------- 1. YEARS THAT THIS DELEGATE HAS --------
        delegate_years = Schedule
          .joins(conference_date: :conference)
          .where("schedules.booker_id = :id OR schedules.target_id = :id", id: delegate.id)
          .pluck("conferences.conference_year")
          .uniq
          .sort

        year = params[:year].presence || delegate_years.last || Date.today.year.to_s
        conference = Conference.find_by(conference_year: year)

        return render json: {
          error: 'Conference not found',
          available_years: delegate_years
        }, status: :not_found unless conference

        # -------- 2. AVAILABLE DATES --------
        available_dates = conference.conference_dates
                                    .order(:on_date)
                                    .pluck(:on_date)

        # -------- 3. SELECT DATE --------
        selected_date =
          if params[:date].present?
            begin
              Date.parse(params[:date])
            rescue ArgumentError
              nil
            end
          else
            # เลือกวันที่ที่ delegate มี schedule จริงก่อน
            cd_with_schedule = Schedule
              .joins(:conference_date)
              .where(conference_dates: { conference_id: conference.id })
              .where("schedules.booker_id = :id OR schedules.target_id = :id", id: delegate.id)
              .order("conference_dates.on_date ASC")
              .select("schedules.*, conference_dates.on_date")
              .first

            cd_with_schedule&.conference_date&.on_date || available_dates.first
          end

        return render json: { error: 'No conference dates' }, status: :not_found if selected_date.nil?

        conference_date = conference.conference_dates.find_by(on_date: selected_date)
        return render json: { error: 'Conference date not found' }, status: :not_found if conference_date.nil?

        # -------- 4. QUERY SCHEDULE --------
        schedules = Schedule
          .includes(:conference_date, booker: :company, target: :company)
          .where(conference_date_id: conference_date.id)
          .where("schedules.booker_id = :id OR schedules.target_id = :id", id: delegate.id)
          .order(:start_at)

        # -------- 5. RESPONSE --------
        render json: {
          available_years: delegate_years,
          year: year,
          available_dates: available_dates,
          date: selected_date,
          schedules: ActiveModelSerializers::SerializableResource.new(
            schedules,
            each_serializer: Api::V1::ScheduleSerializer,
            scope: delegate
          )
        }
      end








    end
  end
end
