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
        return render json: { error: "Not found" }, status: :not_found unless table

        schedules = Schedule.where(table_number: table_number)
                            .includes(:booker, :delegate, :table)
                            .order(:start_at)

        render json: {
          table_number: table_number,
          status:       get_table_status(table_number),
          occupancy:    get_table_occupancy(table_number),
          capacity:     4,
          occupants:    schedules.filter_map { |s| s.booker || s.delegate }.uniq.map do |d|
                          Api::V1::DelegateSerializer.new(d).serializable_hash
                        end,
          timeline:     schedules.map do |s|
                          Api::V1::ScheduleSerializer.new(s, scope: current_delegate).serializable_hash
                        end
        }
      rescue StandardError => e
        Rails.logger.error "Tables#show error: #{e.message}"
        render json: { error: "Internal server error" }, status: :internal_server_error
      end

      # GET /api/v1/tables/time_view
      def time_view
        conference  = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
        target_year = conference&.conference_year&.to_i || FALLBACK_YEAR.call

        user_selected_date     = params[:date].present?
        user_selected_time     = params[:time].present?
        user_selected_datetime = user_selected_date && user_selected_time

        bkk_now    = Time.current.in_time_zone('Asia/Bangkok')
        input_date = params[:date].present? ? params[:date].to_date : bkk_now.to_date
        input_time = params[:time].presence || bkk_now.strftime("%H:%M")

        datetime = parse_bangkok_datetime(target_year, input_date, input_time, bkk_now)

        # ถ้าปีนั้นไม่มีข้อมูล ให้หา actual year จาก DB
        unless schedule_exists_in_year?(target_year)
          actual_year = Schedule
                        .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                        .order(:start_at)
                        .first&.start_at&.in_time_zone('Asia/Bangkok')&.year
          if actual_year
            target_year = actual_year
            datetime    = parse_bangkok_datetime(target_year, input_date, input_time, bkk_now)
          end
        end

        # โหลด schedules ของ datetime นั้น
        schedules = load_schedules_at(datetime)

        # fallback 1: ไม่มีข้อมูลตาม time → ใช้เวลาแรกของวันนั้น
        if schedules.empty? && !user_selected_datetime
          first_of_day = Schedule
                         .where("DATE(start_at AT TIME ZONE 'Asia/Bangkok') = ?", input_date)
                         .where("EXTRACT(YEAR FROM start_at AT TIME ZONE 'Asia/Bangkok') = ?", target_year)
                         .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                         .order(:start_at)
                         .first

          if first_of_day
            datetime  = first_of_day.start_at
            schedules = load_schedules_at(datetime)
          end
        end

        # fallback 2: ไม่มีข้อมูลของวันนั้น → ใช้ schedule แรกสุดของปี
        if schedules.empty? && !user_selected_datetime
          first_of_year = Schedule
                          .where("EXTRACT(YEAR FROM start_at AT TIME ZONE 'Asia/Bangkok') = ?", target_year)
                          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                          .order(:start_at)
                          .first

          if first_of_year
            datetime  = first_of_year.start_at
            schedules = load_schedules_at(datetime)
          end
        end

        # all_times_today: ใช้ conference_date_id เพื่อกัน timezone ข้ามวัน
        # (schedule เวลาเย็น Bangkok เช่น 20:00 UTC = 03:00 Bangkok วันถัดไป
        #  ถ้าใช้ DATE() จะดึงมา 2 วัน → ใช้ conference_date_id แทน)
        bkk_date        = datetime.in_time_zone('Asia/Bangkok').to_date
        conference_date = conference.conference_dates.find_by(on_date: bkk_date)
        conference_date ||= schedules.first&.conference_date

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

        # Layout
        numeric_tables = Table.where("table_number ~ '^[0-9]+$'")
        columns        = detect_columns(numeric_tables)
        total_tables   = numeric_tables.count
        rows           = (total_tables.to_f / columns).ceil
        layout         = { type: "grid", rows: rows, columns: columns }

        all_tables = Table.all.sort_by do |t|
          t.table_number.to_s =~ /^\d+$/ ? [0, t.table_number.to_i] : [1, t.table_number.to_s]
        end

        tables = all_tables.map do |table|
          key             = table.table_number.to_s.strip
          table_schedules = schedule_by_table[key] || []
          meetings        = table_schedules.map { |s| build_meeting_info(s) }

          # delegates flat list (backward compat)
          # booker || delegate เพื่อรองรับทั้ง 2 กรณี (verified: query 1 = 0)
          flat_delegates = table_schedules
                           .flat_map { |s| [s.booker, s.delegate].compact }
                           .uniq(&:id)
                           .map do |d|
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
            delegates:    flat_delegates
          }
        end

        render json: {
          year:        target_year,
          date:        bkk_date,
          time:        datetime.in_time_zone('Asia/Bangkok').iso8601,
          my_table:    my_schedule&.table_number,
          layout:      layout,
          tables:      tables,
          times_today: all_times_today,
          days:        all_days
        }
      end

      private

      def parse_bangkok_datetime(year, date, time_str, fallback)
        Time.zone.parse("#{year}-#{date.strftime('%m-%d')} #{time_str}")
      rescue ArgumentError
        fallback
      end

      def schedule_exists_in_year?(year)
        Schedule
          .where("EXTRACT(YEAR FROM start_at AT TIME ZONE 'Asia/Bangkok') = ?", year)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .exists?
      end

      # includes ครอบคลุมทั้ง booker และ delegate พร้อม company
      def load_schedules_at(datetime)
        Schedule
          .includes(
            :table,
            booker:   :company,
            delegate: :company,
            team:     [:delegates, :company]
          )
          .where(start_at: datetime)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      end

      def detect_columns(numeric_tables)
        first_table = numeric_tables.find_by(table_number: "1")
        return 6 unless first_table

        near     = YAML.safe_load(first_table.adjacent_tables || "--- []")
        vertical = near.map(&:to_i).find { |n| n > 1 && (n - 1) > 1 }
        vertical ? vertical - 1 : 6
      rescue StandardError
        6
      end

      # side_a: booker ก่อน fallback delegate
      #   - verified: Schedule ที่ booker_id=nil AND delegate_id=nil = 0 → side_a ไม่มีทางเป็น null
      # side_b: team via target_id
      #   - verified: ทุก target_id เป็น Team ID → ไม่มีกรณีชนกับ Delegate
      def build_meeting_info(schedule)
        person_a = schedule.booker || schedule.delegate
        team     = schedule.team

        side_a = if person_a
          {
            delegate_id: person_a.id,
            name:        person_a.name,
            title:       person_a.title,
            company_id:  person_a.company_id,
            company:     person_a.company&.name || "N/A",
            avatar_url:  "https://ui-avatars.com/api/?name=#{CGI.escape(person_a.name)}"
          }
        end

        side_b = if team
          members = team.delegates.map do |d|
            {
              id:         d.id,
              name:       d.name,
              title:      d.title,
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
          start_at:    schedule.start_at&.in_time_zone('Asia/Bangkok')&.iso8601,
          end_at:      schedule.end_at&.in_time_zone('Asia/Bangkok')&.iso8601,
          side_a:      side_a,
          side_b:      side_b
        }
      end

      def get_table_status(table_number)
        occupancy = get_table_occupancy(table_number)
        return "empty"   if occupancy.zero?
        return "full"    if occupancy >= 4
        "partial"
      end

      def get_table_occupancy(table_number)
        Schedule.where(table_number: table_number).select(:booker_id).distinct.count
      end
    end
  end
end