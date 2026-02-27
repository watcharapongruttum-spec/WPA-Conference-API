module Api
  module V1
    class TablesController < BaseController
      FALLBACK_YEAR = -> { Date.today.year }

      # GET /api/v1/tables/grid_view
      def grid_view
        conference = Conference.find_by(is_current: true) || Conference.first
        tables = conference ? Table.where(conference_id: conference.id) : Table.none

        render json: tables.map { |table|
          {
            id: table.id,
            table_number: table.table_number,
            status: get_table_status(table.table_number),
            occupancy: get_table_occupancy(table.table_number),
            capacity: 4
          }
        }
      end

      # GET /api/v1/tables/:id
      def show
        table_number = params[:id]

        table = Table.find_by(table_number: table_number)
        return render json: { error: "Not found" }, status: :not_found unless table

        schedules = Schedule.where(table_number: table_number)
                            .includes(:booker, :table)
                            .order(:start_at)

        render json: {
          table_number: table_number,
          status: get_table_status(table_number),
          occupancy: get_table_occupancy(table_number),
          capacity: 4,
          occupants: schedules.filter_map(&:booker).uniq.map do |d|
            Api::V1::DelegateSerializer.new(d).serializable_hash
          end,
          timeline: schedules.map do |s|
            Api::V1::ScheduleSerializer.new(s, scope: current_delegate).serializable_hash
          end
        }
      rescue StandardError => e
        Rails.logger.error "Tables#show error: #{e.message}"
        render json: { error: "Internal server error" }, status: :internal_server_error
      end

      def time_view
        conference  = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
        target_year = conference&.conference_year&.to_i || FALLBACK_YEAR.call

        user_selected_date     = params[:date].present?
        user_selected_time     = params[:time].present?
        user_selected_datetime = user_selected_date && user_selected_time

        # ✅ FIX TIMEZONE: ใช้ Bangkok time zone ตลอด
        # อย่าใช้ Date.today เพราะอาจเป็น UTC — ใช้ Time.current.in_time_zone('Asia/Bangkok').to_date แทน
        bkk_now    = Time.current.in_time_zone('Asia/Bangkok')
        input_date = params[:date].present? ? params[:date].to_date : bkk_now.to_date
        input_time = params[:time] || bkk_now.strftime("%H:%M")

        # ✅ FIX: สร้าง datetime ใน Bangkok zone แบบ explicit
        begin
          datetime = Time.zone.parse("#{target_year}-#{input_date.strftime('%m-%d')} #{input_time}")
        rescue ArgumentError
          datetime = bkk_now
        end

        has_data_in_year = Schedule
                           .where("EXTRACT(YEAR FROM start_at AT TIME ZONE 'Asia/Bangkok') = ?", target_year)
                           .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                           .exists?

        unless has_data_in_year
          actual_year = Schedule
                        .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                        .order(:start_at)
                        .first&.start_at&.in_time_zone('Asia/Bangkok')&.year

          if actual_year
            target_year = actual_year
            begin
              datetime = Time.zone.parse("#{target_year}-#{input_date.strftime('%m-%d')} #{input_time}")
            rescue ArgumentError
              datetime = bkk_now
            end
          end
        end

        schedules = Schedule
                    .includes(:delegate, :booker, :table, team: [:delegates, :company], booker: :company)
                    .where(start_at: datetime)
                    .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")

        if schedules.empty? && !user_selected_datetime
          # ✅ FIX: ใช้ Bangkok date ในการ query
          first_time = Schedule
                       .where("DATE(start_at AT TIME ZONE 'Asia/Bangkok') = ?", input_date)
                       .where("EXTRACT(YEAR FROM start_at AT TIME ZONE 'Asia/Bangkok') = ?", target_year)
                       .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                       .order(:start_at).first

          if first_time
            datetime  = first_time.start_at
            schedules = Schedule
                        .includes(:delegate, :booker, :table, team: [:delegates, :company], booker: :company)
                        .where(start_at: datetime)
                        .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          end
        end

        if schedules.empty? && !user_selected_datetime
          first_schedule = Schedule
                           .where("EXTRACT(YEAR FROM start_at AT TIME ZONE 'Asia/Bangkok') = ?", target_year)
                           .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                           .order(:start_at).first

          if first_schedule
            datetime  = first_schedule.start_at
            schedules = Schedule
                        .includes(:delegate, :booker, :table, team: [:delegates, :company], booker: :company)
                        .where(start_at: datetime)
                        .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          end
        end

        # ✅ FIX: ใช้ Bangkok timezone + Arel.sql() เพื่อกัน Rails 7 raw SQL block
        all_times_today = Schedule
                          .where("DATE(start_at AT TIME ZONE 'Asia/Bangkok') = ?", datetime.in_time_zone('Asia/Bangkok').to_date)
                          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                          .order(:start_at)
                          .pluck(:start_at)
                          .map { |t| t.in_time_zone('Asia/Bangkok').iso8601 }
                          .uniq

        all_days = conference
          .conference_dates
          .joins(:schedules)
          .where("schedules.delegate_id IS NOT NULL OR schedules.booker_id IS NOT NULL")
          .pluck(:on_date)
          .uniq
          .sort

        my_schedule = current_delegate && schedules.find do |s|
          s.delegate_id == current_delegate.id || s.booker_id == current_delegate.id
        end

        schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

        # ✅ FIX times_today: กรองด้วย conference_date_id ไม่ใช่ DATE()
        # เพราะ schedule เวลาเย็น Bangkok (เช่น 20:00 UTC) = 03:00 Bangkok วันถัดไป
        # → ถ้าใช้ DATE() ใน Bangkok zone จะดึงสองวัน
        # conference_date.on_date คือ "วัน" ที่ถูกต้องของ slot ทั้งหมด
        bkk_date = datetime.in_time_zone('Asia/Bangkok').to_date
        conference_date = conference.conference_dates.find_by(on_date: bkk_date)

        # fallback: ถ้าไม่เจอตาม date ให้ดึงจาก schedule ที่ query มาได้
        if conference_date.nil? && schedules.any?
          conference_date = schedules.first.conference_date
        end

        all_times_today = if conference_date
          Schedule
            .where(conference_date_id: conference_date.id)
            .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
            .order(:start_at)
            .pluck(:start_at)
            .map { |t| t.in_time_zone('Asia/Bangkok').iso8601 }
            .uniq
        else
          []
        end

        numeric_tables = Table.where("table_number ~ '^[0-9]+$'")
        first_table    = numeric_tables.find_by(table_number: "1")
        columns        = 6

        if first_table.present?
          begin
            near     = YAML.safe_load(first_table.adjacent_tables || "--- []")
            vertical = near.map(&:to_i).find { |n| n > 1 && (n - 1) > 1 }
            columns  = vertical - 1 if vertical
          rescue StandardError
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

          # ✅ ดึง meeting ทั้ง 2 ฝั่ง (booker + team) สำหรับโต๊ะนี้
          meetings = table_schedules.map { |s| build_meeting_info(s) }

          # backward compat — delegates flat list
          delegates = table_schedules.flat_map do |s|
            people = []
            people << s.delegate if s.delegate.present?
            people << s.booker   if s.booker.present?
            people
          end.uniq(&:id).map do |d|
            {
              delegate_id:   d.id,
              delegate_name: d.name,
              company:       d.company&.name || "N/A",
              avatar_url:    "https://ui-avatars.com/api/?name=#{CGI.escape(d.name)}",
              title:         d.title
            }
          end

          near_tables = begin
            YAML.safe_load(table.adjacent_tables || "--- []")
          rescue StandardError
            []
          end

          {
            table_id:     table.id,
            table_number: table.table_number,
            near_tables:  near_tables,
            meetings:     meetings,
            delegates:    delegates       # backward compat
          }
        end

        render json: {
          year:         target_year,
          date:         datetime.in_time_zone('Asia/Bangkok').to_date,
          time:         datetime.in_time_zone('Asia/Bangkok').iso8601,  # ✅ Bangkok time
          my_table:     my_schedule&.table_number,
          layout:       layout,
          tables:       tables,
          times_today:  all_times_today,
          days:         all_days
        }
      end

      private

      # ✅ สร้าง meeting info 2 ฝั่ง: booker (ผู้จอง) กับ team ที่ถูกจอง
      def build_meeting_info(schedule)
        booker = schedule.booker
        team   = schedule.team   # belongs_to :team, foreign_key: :target_id

        side_a = if booker
          {
            delegate_id: booker.id,
            name:        booker.name,
            title:       booker.title,
            company_id:  booker.company_id,
            company:     booker.company&.name || "N/A",
            avatar_url:  "https://ui-avatars.com/api/?name=#{CGI.escape(booker.name)}"
          }
        end

        side_b = if team
          members = team.delegates.map do |d|
            {
              id:        d.id,
              name:      d.name,
              title:     d.title,
              avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(d.name)}"
            }
          end
          {
            team_id:      team.id,
            team_name:    team.name,
            country_code: team.country_code,
            company:      team.company&.name,
            members:      members,
            member_count: members.size
          }
        end

        {
          schedule_id: schedule.id,
          start_at:    schedule.start_at&.in_time_zone('Asia/Bangkok')&.iso8601,  # ✅ Bangkok
          end_at:      schedule.end_at&.in_time_zone('Asia/Bangkok')&.iso8601,
          side_a:      side_a,   # booker (บริษัทที่จอง)
          side_b:      side_b    # team/บริษัทที่ถูกนัด
        }
      end

      def get_table_status(table_number)
        occupancy = get_table_occupancy(table_number)
        if occupancy.zero?
          "empty"
        else
          occupancy >= 4 ? "full" : "partial"
        end
      end

      def get_table_occupancy(table_number)
        Schedule.where(table_number: table_number).select(:booker_id).distinct.count
      end
    end
  end
end