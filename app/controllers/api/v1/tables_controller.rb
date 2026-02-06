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


      # def time_view
      #   # รับปีจาก params หรือใช้ conference ปัจจุบัน
      #   conference = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
      #   target_year = params[:year]&.to_i || conference&.conference_year&.to_i || FIX_YEAR
        
      #   # รับ date และ time จาก params
      #   input_date = params[:date]&.to_date || Date.today
      #   input_time = params[:time] || Time.current.strftime("%H:%M")
        
      #   # สร้าง datetime จาก input แต่ใช้ปีที่ต้องการ
      #   datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")

      #   # ตรวจสอบว่ามีข้อมูลในปีนี้หรือไม่
      #   has_data_in_year = Schedule.where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #                             .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #                             .exists?

      #   # ถ้าไม่มีข้อมูลในปีที่เลือก ให้หาปีที่มีข้อมูล
      #   unless has_data_in_year
      #     actual_year = Schedule.where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #                         .order(:start_at)
      #                         .first
      #                         &.start_at
      #                         &.year
          
      #     if actual_year
      #       target_year = actual_year
      #       datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")
      #     end
      #   end

      #   # 2. หา schedule ตรงเวลา
      #   schedules = Schedule
      #     .includes(:delegate, :booker, :table)
      #     .where(start_at: datetime)
      #     .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")

      #   # 3. Fallback: หาเวลาน้อยสุดในวันนั้น
      #   if schedules.empty?
      #     first_time = Schedule
      #       .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #       .where("EXTRACT(MONTH FROM start_at) = ?", input_date.month)
      #       .where("EXTRACT(DAY FROM start_at) = ?", input_date.day)
      #       .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #       .order(:start_at)
      #       .first

      #     if first_time
      #       datetime = first_time.start_at
      #       schedules = Schedule
      #         .includes(:delegate, :booker, :table)
      #         .where(start_at: datetime)
      #         .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     end
      #   end

      #   # 4. Fallback: หาวันน้อยสุดในปีที่มีข้อมูล
      #   if schedules.empty?
      #     first_schedule = Schedule
      #       .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #       .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #       .order(:start_at)
      #       .first

      #     if first_schedule
      #       datetime = first_schedule.start_at
      #       schedules = Schedule
      #         .includes(:delegate, :booker, :table)
      #         .where(start_at: datetime)
      #         .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     end
      #   end

      #   # 5. เวลาทั้งหมดในวันนี้
      #   all_times_today = Schedule
      #     .where("DATE(start_at) = ?", datetime.to_date)
      #     .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     .order(:start_at)
      #     .pluck(:start_at)
      #     .map { |t| t.strftime("%H:%M") }
      #     .uniq

      #   # 6. วันทั้งหมดในปีที่มีข้อมูล
      #   all_days = Schedule
      #     .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #     .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     .pluck("DATE(start_at)")
      #     .uniq
      #     .sort

      #   # 7. หาโต๊ะของ current_delegate (เช็คทั้ง delegate_id และ booker_id)
      #   my_schedule = if current_delegate
      #     schedules.find do |s|
      #       s.delegate_id == current_delegate.id || s.booker_id == current_delegate.id
      #     end
      #   end

      #   # 8. จัดกลุ่ม schedules ตาม table_number
      #   schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

      #   # 9. สร้าง table list
      #   all_tables = Table.all.sort_by do |t|
      #     num = t.table_number.to_s
      #     num =~ /^\d+$/ ? [0, num.to_i] : [1, num]
      #   end

      #   tables = all_tables.map do |table|
      #     key = table.table_number.to_s.strip
      #     table_schedules = schedule_by_table[key] || []
          
      #     # ดึงข้อมูล delegate จากทั้ง delegate และ booker
      #     delegates = table_schedules.flat_map do |s|
      #       people = []
      #       # เพิ่ม delegate ถ้ามี
      #       people << s.delegate if s.delegate_id.present? && s.delegate.present?
      #       # เพิ่ม booker ถ้ามี
      #       people << s.booker if s.booker_id.present? && s.booker.present?
      #       people
      #     end
      #     .uniq { |d| d.id }
      #     .map do |delegate|
      #       {
      #         delegate_id: delegate.id,
      #         delegate_name: delegate.name,
      #         company: delegate.company&.name || 'N/A',
      #         avatar_url: begin
      #           Api::V1::DelegateSerializer.new(delegate).avatar_url
      #         rescue => e
      #           "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff"
      #         end,
      #         title: delegate.title
      #       }
      #     end

      #     {
      #       table_id: table.id,
      #       table_number: table.table_number,
      #       delegates: delegates
      #     }
      #   end

      #   render json: {
      #     year: target_year,
      #     date: datetime.to_date,
      #     time: datetime.strftime("%H:%M"),
      #     my_table: my_schedule&.table_number,
      #     tables: tables,
      #     times_today: all_times_today,
      #     days: all_days
      #   }
      # end



      # def time_view
      #   # ใช้ปีจาก conference ปัจจุบันเท่านั้น (ไม่ยอมรับจาก params)
      #   conference = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
      #   target_year = conference&.conference_year&.to_i || FIX_YEAR
        
      #   # รับเฉพาะ date และ time จาก params
      #   input_date = params[:date]&.to_date || Date.today
      #   input_time = params[:time] || Time.current.strftime("%H:%M")
        
      #   # สร้าง datetime โดยใช้ปีจาก conference + เดือน/วัน/เวลาจาก params
      #   datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")

      #   # ตรวจสอบว่ามีข้อมูลในปีนี้หรือไม่
      #   has_data_in_year = Schedule.where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #                             .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #                             .exists?

      #   # ถ้าไม่มีข้อมูลในปีที่เลือก ให้หาปีที่มีข้อมูล
      #   unless has_data_in_year
      #     actual_year = Schedule.where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #                         .order(:start_at)
      #                         .first
      #                         &.start_at
      #                         &.year
          
      #     if actual_year
      #       target_year = actual_year
      #       datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")
      #     end
      #   end

      #   # 2. หา schedule ตรงเวลา
      #   schedules = Schedule
      #     .includes(:delegate, :booker, :table)
      #     .where(start_at: datetime)
      #     .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")

      #   # 3. Fallback: หาเวลาน้อยสุดในวันนั้น
      #   if schedules.empty?
      #     first_time = Schedule
      #       .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #       .where("EXTRACT(MONTH FROM start_at) = ?", input_date.month)
      #       .where("EXTRACT(DAY FROM start_at) = ?", input_date.day)
      #       .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #       .order(:start_at)
      #       .first

      #     if first_time
      #       datetime = first_time.start_at
      #       schedules = Schedule
      #         .includes(:delegate, :booker, :table)
      #         .where(start_at: datetime)
      #         .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     end
      #   end

      #   # 4. Fallback: หาวันน้อยสุดในปีที่มีข้อมูล
      #   if schedules.empty?
      #     first_schedule = Schedule
      #       .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #       .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #       .order(:start_at)
      #       .first

      #     if first_schedule
      #       datetime = first_schedule.start_at
      #       schedules = Schedule
      #         .includes(:delegate, :booker, :table)
      #         .where(start_at: datetime)
      #         .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     end
      #   end

      #   # 5. เวลาทั้งหมดในวันนี้
      #   all_times_today = Schedule
      #     .where("DATE(start_at) = ?", datetime.to_date)
      #     .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     .order(:start_at)
      #     .pluck(:start_at)
      #     .map { |t| t.strftime("%H:%M") }
      #     .uniq

      #   # 6. วันทั้งหมดในปีที่มีข้อมูล
      #   all_days = Schedule
      #     .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
      #     .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      #     .pluck("DATE(start_at)")
      #     .uniq
      #     .sort

      #   # 7. หาโต๊ะของ current_delegate (เช็คทั้ง delegate_id และ booker_id)
      #   my_schedule = if current_delegate
      #     schedules.find do |s|
      #       s.delegate_id == current_delegate.id || s.booker_id == current_delegate.id
      #     end
      #   end

      #   # 8. จัดกลุ่ม schedules ตาม table_number
      #   schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

      #   # 9. สร้าง table list
      #   all_tables = Table.all.sort_by do |t|
      #     num = t.table_number.to_s
      #     num =~ /^\d+$/ ? [0, num.to_i] : [1, num]
      #   end

      #   tables = all_tables.map do |table|
      #     key = table.table_number.to_s.strip
      #     table_schedules = schedule_by_table[key] || []
          
      #     # ดึงข้อมูล delegate จากทั้ง delegate และ booker
      #     delegates = table_schedules.flat_map do |s|
      #       people = []
      #       # เพิ่ม delegate ถ้ามี
      #       people << s.delegate if s.delegate_id.present? && s.delegate.present?
      #       # เพิ่ม booker ถ้ามี
      #       people << s.booker if s.booker_id.present? && s.booker.present?
      #       people
      #     end
      #     .uniq { |d| d.id }
      #     .map do |delegate|
      #       {
      #         delegate_id: delegate.id,
      #         delegate_name: delegate.name,
      #         company: delegate.company&.name || 'N/A',
      #         avatar_url: begin
      #           Api::V1::DelegateSerializer.new(delegate).avatar_url
      #         rescue => e
      #           "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff"
      #         end,
      #         title: delegate.title
      #       }
      #     end

      #     {
      #       table_id: table.id,
      #       table_number: table.table_number,
      #       delegates: delegates
      #     }
      #   end

      #   render json: {
      #     year: target_year,
      #     date: datetime.to_date,
      #     time: datetime.strftime("%H:%M"),
      #     my_table: my_schedule&.table_number,
      #     tables: tables,
      #     times_today: all_times_today,
      #     days: all_days
      #   }
      # end


      def time_view
        # ใช้ปีจาก conference ปัจจุบันเท่านั้น
        conference = Conference.find_by(is_current: true) || Conference.order(conference_year: :desc).first
        target_year = conference&.conference_year&.to_i || FIX_YEAR

        # ตรวจว่าผู้ใช้เลือกวัน/เวลาเองหรือไม่
        user_selected_date = params[:date].present?
        user_selected_time = params[:time].present?
        user_selected_datetime = user_selected_date && user_selected_time

        # รับ date / time
        input_date = params[:date]&.to_date || Date.today
        input_time = params[:time] || "00:00"

        # สร้าง datetime
        datetime = Time.zone.parse("#{target_year}-#{input_date.month}-#{input_date.day} #{input_time}")

        # -----------------------------
        # ตรวจว่าปีนี้มีข้อมูลหรือไม่
        # -----------------------------
        has_data_in_year = Schedule.where("EXTRACT(YEAR FROM start_at) = ?", target_year)
                                    .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                                    .exists?

        # ถ้าไม่มีข้อมูลในปี conference → หา actual ปี
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
        # 1. หา schedule ตรงเวลา
        # -----------------------------
        schedules = Schedule
          .includes(:delegate, :booker, :table)
          .where(start_at: datetime)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")

        # -----------------------------
        # 2. Fallback เวลาแรกของวัน (เฉพาะ user ไม่เลือกเวลา)
        # -----------------------------
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

        # -----------------------------
        # 3. Fallback วันแรกของปี (เฉพาะ user ไม่เลือกอะไรเลย)
        # -----------------------------
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
        # 4. เวลาทั้งหมดในวันนี้
        # -----------------------------
        all_times_today = Schedule
          .where("DATE(start_at) = ?", datetime.to_date)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .order(:start_at)
          .pluck(:start_at)
          .map { |t| t.strftime("%H:%M") }
          .uniq

        # -----------------------------
        # 5. วันทั้งหมดในปี
        # -----------------------------
        all_days = Schedule
          .where("EXTRACT(YEAR FROM start_at) = ?", target_year)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .pluck("DATE(start_at)")
          .uniq
          .sort

        # -----------------------------
        # 6. หาโต๊ะของ current_delegate
        # -----------------------------
        my_schedule = if current_delegate
          schedules.find do |s|
            s.delegate_id == current_delegate.id || s.booker_id == current_delegate.id
          end
        end

        # -----------------------------
        # 7. group ตามโต๊ะ
        # -----------------------------
        schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

        # -----------------------------
        # 8. รายชื่อโต๊ะทั้งหมด
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
            people << s.delegate if s.delegate_id.present? && s.delegate.present?
            people << s.booker if s.booker_id.present? && s.booker.present?
            people
          end
          .uniq { |d| d.id }
          .map do |delegate|
            {
              delegate_id: delegate.id,
              delegate_name: delegate.name,
              company: delegate.company&.name || 'N/A',
              avatar_url: begin
                Api::V1::DelegateSerializer.new(delegate).avatar_url
              rescue
                "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff"
              end,
              title: delegate.title
            }
          end

          {
            table_id: table.id,
            table_number: table.table_number,
            delegates: delegates
          }
        end

        render json: {
          year: target_year,
          date: datetime.to_date,
          time: datetime.strftime("%H:%M"),
          my_table: my_schedule&.table_number,
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