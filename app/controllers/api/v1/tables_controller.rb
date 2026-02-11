module Api
  module V1
    class TablesController < BaseController
      
      # ย้าย FIX_YEAR มาไว้ที่นี่แทน
      FIX_YEAR = 2025
      
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



      
      def time_view
        # -----------------------------
        # YEAR LOGIC
        # -----------------------------
        conference = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
        target_year = conference&.conference_year&.to_i || FIX_YEAR

        user_selected_date = params[:date].present?
        user_selected_time = params[:time].present?
        user_selected_datetime = user_selected_date && user_selected_time

        input_date = params[:date]&.to_date || Date.today
        input_time = params[:time] || "00:00"

        datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")

        # -----------------------------
        # YEAR FALLBACK
        # -----------------------------
        has_data_in_year = Schedule.where("EXTRACT(YEAR FROM start_at) = ?", target_year)
                                    .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                                    .exists?

        unless has_data_in_year
          actual_year = Schedule.where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                                .order(:start_at)
                                .first
                                &.start_at
                                &.year

          if actual_year
            target_year = actual_year
            datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")
          end
        end

        # -----------------------------
        # SCHEDULE FIND
        # -----------------------------
        schedules = Schedule
          .includes(:delegate, :booker, :table)
          .where(start_at: datetime)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")

        if schedules.empty? && !user_selected_datetime
          first_time = Schedule
            .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
            .where("EXTRACT(MONTH FROM start_at) = ?", input_date.month)
            .where("EXTRACT(DAY FROM start_at) = ?", input_date.day)
            .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
            .order(:start_at)
            .first

          if first_time
            datetime = first_time.start_at
            schedules = Schedule
              .includes(:delegate, :booker, :table)
              .where(start_at: datetime)
              .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          end
        end

        if schedules.empty? && !user_selected_datetime
          first_schedule = Schedule
            .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
            .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
            .order(:start_at)
            .first

          if first_schedule
            datetime = first_schedule.start_at
            schedules = Schedule
              .includes(:delegate, :booker, :table)
              .where(start_at: datetime)
              .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          end
        end

        # -----------------------------
        # TIMES / DAYS
        # -----------------------------
        all_times_today = Schedule
          .where("DATE(start_at) = ?", datetime.to_date)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .order(:start_at)
          .pluck(:start_at)
          .map { |t| t.strftime("%I:%M %p") }
          .uniq

        all_days = Schedule
          .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .pluck("DATE(start_at)")
          .uniq
          .sort

        # -----------------------------
        # MY TABLE
        # -----------------------------
        my_schedule = if current_delegate
          schedules.find do |s|
            s.delegate_id == current_delegate.id || s.booker_id == current_delegate.id
          end
        end

        # -----------------------------
        # GROUP BY TABLE
        # -----------------------------
        schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

        # -----------------------------
        # LAYOUT CALC FROM ADJACENT
        # -----------------------------
        numeric_tables = Table.where("table_number ~ '^[0-9]+$'")
        first_table = numeric_tables.find_by(table_number: "1")

        columns = 6 # fallback

        if first_table.present?
          begin
            near = YAML.safe_load(first_table.adjacent_tables || "--- []")
            vertical = near.map(&:to_i).find { |n| n > 1 && (n - 1) > 1 }
            columns = vertical - 1 if vertical
          rescue
            columns = 6
          end
        end

        total_tables = numeric_tables.count
        rows = (total_tables.to_f / columns).ceil

        layout = {
          type: "grid",
          rows: rows,
          columns: columns
        }

        # -----------------------------
        # TABLE LIST
        # -----------------------------
        all_tables = Table.all.sort_by do |t|
          num = t.table_number.to_s
          num =~ /^\d+$/ ? [0, num.to_i] : [1, num]
        end

        tables = all_tables.map do |table|
          key = table.table_number.to_s.strip
          table_schedules = schedule_by_table[key] || []

          delegates = table_schedules.flat_map do |s|
            people = []
            people << s.delegate if s.delegate.present?
            people << s.booker if s.booker.present?
            people
          end
          .uniq { |d| d.id }
          .map do |delegate|
            {
              delegate_id: delegate.id,
              delegate_name: delegate.name,
              company: delegate.company&.name || 'N/A',
              avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}",
              title: delegate.title
            }
          end

          near_tables = begin
            YAML.safe_load(table.adjacent_tables || "--- []")
          rescue
            []
          end

          {
            table_id: table.id,
            table_number: table.table_number,
            near_tables: near_tables,
            delegates: delegates
          }
        end

        # -----------------------------
        # RENDER
        # -----------------------------
        render json: {
          year: target_year,
          date: datetime.to_date,
          time: datetime.strftime("%I:%M %p"),
          my_table: my_schedule&.table_number,
          layout: layout,
          tables: tables,
          times_today: all_times_today,
          days: all_days
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