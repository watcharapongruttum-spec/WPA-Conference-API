module Api
  module V1
    class SchedulesController < ApplicationController

      # ===============================
      # MY SCHEDULE
      # ===============================
      def my_schedule
        filter_date   = parse_date_param! or return
        conference_id = fetch_conference_id! or return
        delegate_id   = current_delegate.id

        render json: build_response(conference_id, filter_date, delegate_id, label: "my_schedule")
      end

      # ===============================
      # SCHEDULE OTHERS
      # ===============================
      def schedule_others
        return render json: { error: "delegate_id is required." },
                      status: :unprocessable_entity unless params[:delegate_id].present?

        target_delegate = Delegate.find_by(id: params[:delegate_id])
        return render json: { error: "Delegate not found." },
                      status: :not_found unless target_delegate

        filter_date   = parse_date_param! or return
        conference_id = fetch_conference_id! or return

        render json: build_response(conference_id, filter_date, target_delegate.id, label: "schedule_others").merge(
          user: Api::V1::DelegateSerializer.new(target_delegate)
        )
      end

      private

      # ===============================
      # BUILD RESPONSE
      # ===============================
      def build_response(conference_id, filter_date, delegate_id, label:)
        rows          = Schedule.timeline_rows(conference_id: conference_id, filter_date: filter_date, delegate_id: delegate_id, label: label)
        selected_year = params[:year]&.to_i || filter_date.year

        {
          years:           Schedule.available_years(conference_id: conference_id),
          year:            selected_year.to_s,
          available_dates: Schedule.available_dates(conference_id: conference_id, year: selected_year),
          selected_date:   filter_date.to_s,
          schedules:       Schedule.format_timeline(rows)
        }
      end

      # ===============================
      # PARAM HELPERS
      # ===============================
      # def parse_date_param!
      #   if params[:date].present?
      #     begin
      #       Date.parse(params[:date].to_s)
      #     rescue ArgumentError, TypeError
      #       render json: { error: "Invalid date format. Use YYYY-MM-DD." },
      #              status: :unprocessable_entity
      #       nil
      #     end
      #   else
      #     # Date.today
      #     Date.new(2025, 10, 13)
      #   end
      # end

      def parse_date_param!
        if params[:date].present?
          begin
            Time.zone.parse(params[:date].to_s)
          rescue ArgumentError, TypeError
            render json: { error: "Invalid date format. Use YYYY-MM-DD or ISO8601." },
                  status: :unprocessable_entity
            nil
          end
        else
          Time.zone.parse("2025-10-13T11:00:00+07:00") 
        end
      end









      def fetch_conference_id!
        conference_id = Reservation.find(current_delegate.reservation_id).conference_id
        unless conference_id
          render json: { error: "Conference not found for this delegate." }, status: :not_found
          return nil
        end
        conference_id
      end

    end
  end
end