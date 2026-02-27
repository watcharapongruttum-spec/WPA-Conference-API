module Api
  module V1
    class TablesController < BaseController

      FALLBACK_YEAR = -> { Date.today.year }

      # GET /api/v1/tables/grid_view
      def grid_view
        conference = Conference.find_by(is_current: true) || Conference.first

        # ✅ FIX: เดิมใช้ conference&.tables ซึ่ง return raw Table AR objects
        # ไม่มี status/occupancy/capacity — ต้องดึงและ format เอง
        tables = conference ? Table.where(conference_id: conference.id) : Table.none

        render json: tables.map { |table|
          {
            id:           table.id,
            table_number: table.table_number,
            status:       get_table_status(table.table_number),
            occupancy:    get_table_occupancy(table.table_number),
            capacity:     4
          }
        }
      end

      # GET /api/v1/tables/:id
      def show
        table_number = params[:id]

        table = Table.find_by(table_number: table_number)
        return render json: { error: 'Not found' }, status: :not_found unless table

        schedules = Schedule.where(table_number: table_number)
                            .includes(:booker, :table)
                            .order(:start_at)

        render json: {
          table_number: table_number,
          status:       get_table_status(table_number),
          occupancy:    get_table_occupancy(table_number),
          capacity:     4,
          occupants:    schedules.filter_map(&:booker).uniq.map do |d|
            Api::V1::DelegateSerializer.new(d).serializable_hash
          end,
          timeline:     schedules.map do |s|
            Api::V1::ScheduleSerializer.new(s, scope: current_delegate).serializable_hash
          end
        }
      rescue => e
        Rails.logger.error "Tables#show error: #{e.message}"
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end

      def time_view
        conference  = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
        target_year = conference&.conference_year&.to_i || FALLBACK_YEAR.call

        user_selected_date     = params[:date].present?
        user_selected_time     = params[:time].present?
        user_selected_datetime = user_selected_date && user_selected_time

        input_date = params[:date]&.to_date || Date.today
        input_time = params[:time] || "00:00"

        datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")

        has_data_in_year = Schedule
          .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .exists?

        unless has_data_in_year
          actual_year = Schedule
            .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
            .order(:start_at)
            .first&.start_at&.year

          if actual_year
            target_year = actual_year
            datetime    = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")
          end
        end

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
            .order(:start_at).first

          if first_time
            datetime  = first_time.start_at
            schedules = Schedule.includes(:delegate, :booker, :table)
                                .where(start_at: datetime)
                                .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          end
        end

        if schedules.empty? && !user_selected_datetime
          first_schedule = Schedule
            .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
            .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
            .order(:start_at).first

          if first_schedule
            datetime  = first_schedule.start_at
            schedules = Schedule.includes(:delegate, :booker, :table)
                                .where(start_at: datetime)
                                .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          end
        end

        all_times_today = Schedule
          .where("DATE(start_at) = ?", datetime.to_date)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .order(:start_at)
          .pluck(:start_at)
          .map { |t| t.utc.iso8601(3) }
          .uniq

        all_days = Schedule
          .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .pluck("DATE(start_at)").uniq.sort

        my_schedule = current_delegate && schedules.find do |s|
          s.delegate_id == current_delegate.id || s.booker_id == current_delegate.id
        end

        schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

        numeric_tables = Table.where("table_number ~ '^[0-9]+$'")
        first_table    = numeric_tables.find_by(table_number: "1")
        columns        = 6

        if first_table.present?
          begin
            near     = YAML.safe_load(first_table.adjacent_tables || "--- []")
            vertical = near.map(&:to_i).find { |n| n > 1 && (n - 1) > 1 }
            columns  = vertical - 1 if vertical
          rescue
            columns = 6
          end
        end

        total_tables = numeric_tables.count
        rows         = (total_tables.to_f / columns).ceil
        layout       = { type: "grid", rows: rows, columns: columns }

        all_tables = Table.all.sort_by do |t|
          num = t.table_number.to_s
          num =~ /^\d+$/ ? [0, num.to_i] : [1, num]
        end

        tables = all_tables.map do |table|
          key             = table.table_number.to_s.strip
          table_schedules = schedule_by_table[key] || []

          delegates = table_schedules.flat_map do |s|
            people = []
            people << s.delegate if s.delegate.present?
            people << s.booker   if s.booker.present?
            people
          end.uniq { |d| d.id }.map do |d|
            {
              delegate_id:   d.id,
              delegate_name: d.name,
              company:       d.company&.name || 'N/A',
              avatar_url:    "https://ui-avatars.com/api/?name=#{CGI.escape(d.name)}",
              title:         d.title
            }
          end

          near_tables = YAML.safe_load(table.adjacent_tables || "--- []") rescue []

          { table_id: table.id, table_number: table.table_number,
            near_tables: near_tables, delegates: delegates }
        end

        render json: {
          year:        target_year,
          date:        datetime.to_date,
          time:        datetime.utc.iso8601(3),
          my_table:    my_schedule&.table_number,
          layout:      layout,
          tables:      tables,
          times_today: all_times_today,
          days:        all_days
        }
      end

      private

      def get_table_status(table_number)
        occupancy = get_table_occupancy(table_number)
        occupancy == 0 ? 'empty' : occupancy >= 4 ? 'full' : 'partial'
      end

      def get_table_occupancy(table_number)
        Schedule.where(table_number: table_number).select(:booker_id).distinct.count
      end
    end
  end
end