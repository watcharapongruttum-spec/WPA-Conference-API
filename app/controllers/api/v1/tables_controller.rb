module Api
  module V1
    class TablesController < BaseController

      TARGET_YEAR = 2025
      BKK_ZONE    = 'Asia/Bangkok'

      # ============================================================
      # TIME VIEW
      # ============================================================
      def time_view
        bkk_now = Time.current.in_time_zone(BKK_ZONE)

        # ----------------------------
        # Robust date parsing
        # รองรับ 2025-10-1 และ 2025-10-01
        # ----------------------------
        input_date =
          if params[:date].present?
            begin
              parts = params[:date].split("-").map(&:to_i)
              Date.new(parts[0], parts[1], parts[2])
            rescue
              bkk_now.to_date
            end
          else
            bkk_now.to_date
          end

        input_time = params[:time] || bkk_now.strftime("%H:%M")

        begin
          hour, minute = input_time.split(":").map(&:to_i)

          datetime = Time.find_zone!(BKK_ZONE).local(
            TARGET_YEAR,
            input_date.month,
            input_date.day,
            hour,
            minute
          )
        rescue
          datetime = bkk_now
        end

        # ============================================================
        # QUERY SCHEDULE (Timezone Safe + Year Locked)
        # ============================================================

        schedules = Schedule
          .includes(:delegate, :booker, :table,
                    team: [:delegates, :company],
                    booker: :company)
          .where(start_at: datetime)
          .where("EXTRACT(YEAR FROM start_at AT TIME ZONE ?) = ?", BKK_ZONE, TARGET_YEAR)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")

        # ถ้าไม่ได้ระบุ exact datetime → ดึง slot แรกของปี 2025
        if schedules.empty? && !(params[:date].present? && params[:time].present?)
          first_schedule = Schedule
            .where("EXTRACT(YEAR FROM start_at AT TIME ZONE ?) = ?", BKK_ZONE, TARGET_YEAR)
            .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
            .order(:start_at)
            .first

          if first_schedule
            datetime = first_schedule.start_at
            schedules = Schedule
              .includes(:delegate, :booker, :table,
                        team: [:delegates, :company],
                        booker: :company)
              .where(start_at: datetime)
              .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          end
        end

        # ============================================================
        # ALL TIMES TODAY (Timezone Safe)
        # ============================================================

        all_times_today = Schedule
          .where("DATE(start_at AT TIME ZONE ?) = ?",
                 BKK_ZONE,
                 datetime.in_time_zone(BKK_ZONE).to_date)
          .where("EXTRACT(YEAR FROM start_at AT TIME ZONE ?) = ?", BKK_ZONE, TARGET_YEAR)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .order(:start_at)
          .pluck(:start_at)
          .map { |t| t.in_time_zone(BKK_ZONE).iso8601 }
          .uniq

        # ============================================================
        # ALL DAYS IN YEAR
        # ============================================================

        all_days = Schedule
          .where("EXTRACT(YEAR FROM start_at AT TIME ZONE ?) = ?", BKK_ZONE, TARGET_YEAR)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .pluck(Arel.sql("DATE(start_at AT TIME ZONE '#{BKK_ZONE}')"))
          .uniq
          .sort

        # ============================================================
        # TABLE FILTER (เฉพาะ conference ปี 2025)
        # ============================================================

        conference_2025 = Conference.find_by(conference_year: TARGET_YEAR)

        tables_scope =
          if conference_2025
            Table.where(conference_id: conference_2025.id)
          else
            Table.none
          end

        schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

        tables = tables_scope.order(:table_number).map do |table|
          key = table.table_number.to_s.strip
          table_schedules = schedule_by_table[key] || []

          {
            table_id:     table.id,
            table_number: table.table_number,
            meetings:     table_schedules.map { |s| build_meeting_info(s) }
          }
        end

        render json: {
          year: TARGET_YEAR,
          date: datetime.in_time_zone(BKK_ZONE).to_date,
          time: datetime.in_time_zone(BKK_ZONE).iso8601,
          tables: tables,
          times_today: all_times_today,
          days: all_days
        }
      end

      # ============================================================
      # PRIVATE
      # ============================================================

      private

      def build_meeting_info(schedule)
        booker = schedule.booker
        team   = schedule.team

        side_a = if booker
          {
            delegate_id: booker.id,
            name:        booker.name,
            title:       booker.title,
            company_id:  booker.company_id,
            company:     booker.company&.name,
            avatar_url:  "https://ui-avatars.com/api/?name=#{CGI.escape(booker.name)}"
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
            company:      team.company&.name,
            country_code: team.country_code,
            members:      members,
            member_count: members.size
          }
        end

        {
          schedule_id: schedule.id,
          start_at:    schedule.start_at&.in_time_zone(BKK_ZONE)&.iso8601,
          end_at:      schedule.end_at&.in_time_zone(BKK_ZONE)&.iso8601,
          side_a:      side_a,
          side_b:      side_b
        }
      end
    end
  end
end