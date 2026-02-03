module Api
  module V1
    class TablesController < BaseController
      
      # GET /api/v1/tables/grid_view
      def grid_view
        conference = Conference.find_by(is_current: true) || Conference.first
        @tables = conference&.tables || []
        
        render json: @tables.map do |table|
          {
            id: table.id,
            table_number: table.table_number,
            status: get_table_status(table.table_number),
            occupancy: get_table_occupancy(table.table_number),
            capacity: 4
          }
        end
      end
      
      # GET /api/v1/tables/:id
      def show
        table_number = params[:id]
        
        schedules = Schedule.where(table_number: table_number)
                           .includes(:booker, :target, :conference_date)
                           .order(:start_at)
        
        render json: {
          table_number: table_number,
          status: get_table_status(table_number),
          occupancy: get_table_occupancy(table_number),
          capacity: 4,
          occupants: schedules.map { |s| s.booker }.uniq.map do |d|
            Api::V1::DelegateSerializer.new(d).serializable_hash
          end,
          timeline: schedules.map do |s|
            Api::V1::ScheduleSerializer.new(s, scope: current_delegate).serializable_hash
          end
        }
      end
      
      private
      
      def get_table_status(table_number)
        occupancy = get_table_occupancy(table_number)
        if occupancy == 0
          'empty'
        elsif occupancy >= 4
          'full'
        else
          'partial'
        end
      end
      
      def get_table_occupancy(table_number)
        Schedule.where(table_number: table_number)
                .select(:booker_id)
                .distinct
                .count
      end
    end
  end
end