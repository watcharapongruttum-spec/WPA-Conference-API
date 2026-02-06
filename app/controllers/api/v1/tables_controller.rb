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

      # GET /api/v1/tables/time_view
      def time_view
        # รับปีจาก params หรือใช้ conference ปัจจุบัน
        conference = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
        target_year = params[:year]&.to_i || conference&.conference_year&.to_i || FIX_YEAR
        
        # รับ date และ time จาก params
        input_date = params[:date]&.to_date || Date.today
        input_time = params[:time] || Time.current.strftime("%H:%M")
        
        # สร้าง datetime จาก input แต่ใช้ปีที่ต้องการ
        datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")

        # 2. หา schedule ตรงเวลาในปีที่เลือก
        schedules = Schedule
          .includes(:delegate, :table)
          .where(start_at: datetime)
          .where.not(delegate_id: nil)

        # 3. Fallback: หาเวลาน้อยสุดในวันนั้น (ใช้วันที่จาก input)
        if schedules.empty?
          first_time = Schedule
            .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
            .where("EXTRACT(MONTH FROM start_at) = ?", input_date.month)
            .where("EXTRACT(DAY FROM start_at) = ?", input_date.day)
            .where.not(delegate_id: nil)
            .order(:start_at)
            .first

          if first_time
            datetime = first_time.start_at
            schedules = Schedule
              .includes(:delegate, :table)
              .where(start_at: datetime)
              .where.not(delegate_id: nil)
          end
        end

        # 4. Fallback: หาวันน้อยสุดในปีที่เลือก
        if schedules.empty?
          first_schedule = Schedule
            .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
            .where.not(delegate_id: nil)
            .order(:start_at)
            .first

          if first_schedule
            datetime = first_schedule.start_at
            schedules = Schedule
              .includes(:delegate, :table)
              .where(start_at: datetime)
              .where.not(delegate_id: nil)
          end
        end

        # 5. เวลาทั้งหมดในวันนี้
        all_times_today = Schedule
          .where("DATE(start_at) = ?", datetime.to_date)
          .where.not(delegate_id: nil)
          .order(:start_at)
          .pluck(:start_at)
          .map { |t| t.strftime("%H:%M") }
          .uniq

        # 6. วันทั้งหมดในปีที่เลือก
        all_days = Schedule
          .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
          .where.not(delegate_id: nil)
          .pluck("DATE(start_at)")
          .uniq
          .sort

        # 7. หาโต๊ะของ current_delegate
        my_schedule = if current_delegate
          schedules.find { |s| s.delegate_id == current_delegate.id }
        end

        # 8. จัดกลุ่ม schedules ตาม table_number
        schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

        # 9. สร้าง table list (เรียงเลขโต๊ะ + booth ไปท้าย)
        all_tables = Table.includes(teams: :delegates).all.sort_by do |t|
          num = t.table_number.to_s
          num =~ /^\d+$/ ? [0, num.to_i] : [1, num]
        end

        tables = all_tables.map do |table|
          key = table.table_number.to_s.strip
          table_schedules = schedule_by_table[key] || []
          
          # ใช้ข้อมูลจาก schedules (ตามช่วงเวลา)
          delegates = table_schedules
            .select { |s| s.delegate_id.present? && s.delegate.present? }
            .uniq { |s| s.delegate_id }
            .map do |s|
              delegate = s.delegate
              {
                delegate_id: delegate.id,
                delegate_name: delegate.name,
                company: delegate.company&.name || 'N/A',
                avatar_url: begin
                  Api::V1::DelegateSerializer.new(delegate).avatar_url
                rescue => e
                  "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff"
                end,
                title: delegate.title
              }
            end

          {
            table_id: table.id,
            table_number: table.table_number,
            delegates: delegates,
            occupancy: delegates.count
          }
        end

        # 10. Render response
        render json: {
          year: target_year,
          date: datetime.to_date,
          time: datetime.strftime("%H:%M"),
          my_table: my_schedule&.table_number,
          
          tables: tables,
          
          times_today: all_times_today,
          
          days: all_days,
          total_days: all_days.count
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