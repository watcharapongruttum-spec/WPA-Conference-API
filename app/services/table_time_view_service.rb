# app/services/table_time_view_service.rb
#
# รับผิดชอบ logic ทั้งหมดของ GET /api/v1/tables/time_view
# Controller แค่เรียก .call แล้ว render json
#
class TableTimeViewService
  TIMEZONE = "Asia/Bangkok"

  # ────────────────────────────────────────────
  # Entry point
  # ────────────────────────────────────────────
  def self.call(params:, current_delegate: nil)
    new(params: params, current_delegate: current_delegate).call
  end

  def initialize(params:, current_delegate: nil)
    @params           = params
    @current_delegate = current_delegate
  end

  def call
    resolve_conference
    resolve_datetime
    resolve_schedules
    resolve_conference_date
    build_result
  end

  # ────────────────────────────────────────────
  # 1. Conference + year
  # ────────────────────────────────────────────
  private

  def resolve_conference
    @conference  = Conference.find_by(is_current: true) ||
                   Conference.order(conference_year: :desc).first
    @target_year = @conference&.conference_year&.to_i || Date.today.year

    # fallback: ถ้าปีนี้ไม่มี schedule เลย → หาปีจริงจาก DB
    unless schedule_exists_in_year?(@target_year)
      actual = Schedule
                 .where("booker_id IS NOT NULL")
                 .order(:start_at)
                 .pick(Arel.sql("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}')::int"))
      @target_year = actual if actual
    end
  end

  # ────────────────────────────────────────────
  # 2. Resolve datetime จาก params
  # ────────────────────────────────────────────
  def resolve_datetime
    @input_date            = parse_date_param(@params[:date])
    @input_time            = parse_time_param(@params[:time])
    @time_only_given       = @params[:date].blank? && @params[:time].present?
    @user_selected_datetime = @params[:date].present? && @params[:time].present?

    bkk_now     = Time.current.in_time_zone(TIMEZONE)
    @input_date ||= bkk_now.to_date
    @input_time ||= bkk_now.strftime("%H:%M")

    # ถ้าส่งแค่ ?time= (ไม่มี date) → ใช้วันแรกของ conference จริง
    if @time_only_given
      first_day = @conference
                    .conference_dates
                    .joins(:schedules)
                    .where("schedules.booker_id IS NOT NULL")
                    .order(:on_date)
                    .pick(:on_date)
      @input_date = first_day if first_day
    end

    @datetime = parse_bangkok_datetime(@target_year, @input_date, @input_time, bkk_now)
  end

  # ────────────────────────────────────────────
  # 3. Load schedules + fallbacks
  # ────────────────────────────────────────────
  def resolve_schedules
    @schedules = load_schedules_at(@datetime)

    # fallback 1: เวลาแรกของวันนั้น
    if @schedules.empty? && !@user_selected_datetime
      first_of_day = Schedule
        .where("DATE(start_at AT TIME ZONE '#{TIMEZONE}') = ?", @input_date)
        .where("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}') = ?", @target_year)
        .where("booker_id IS NOT NULL")
        .order(:start_at)
        .pick(:start_at)

      if first_of_day
        @datetime  = first_of_day
        @schedules = load_schedules_at(@datetime)
      end
    end

    # fallback 2: schedule แรกของปี
    if @schedules.empty? && !@user_selected_datetime
      first_of_year = Schedule
        .where("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}') = ?", @target_year)
        .where("booker_id IS NOT NULL")
        .order(:start_at)
        .pick(:start_at)

      if first_of_year
        @datetime  = first_of_year
        @schedules = load_schedules_at(@datetime)
      end
    end
  end

  # ────────────────────────────────────────────
  # 4. Conference date (สำหรับ times_today)
  # ────────────────────────────────────────────
  def resolve_conference_date
    bkk_date        = @datetime.in_time_zone(TIMEZONE).to_date
    @bkk_date       = bkk_date
    @conference_date = @conference&.conference_dates&.find_by(on_date: bkk_date)
    @conference_date ||= @schedules.first&.conference_date
  end

  # ────────────────────────────────────────────
  # 5. Build final response hash
  # ────────────────────────────────────────────
  def build_result
    all_times_today = times_today
    all_days        = conference_days
    all_tables      = sorted_tables
    adjacent_by_id  = parse_adjacent_tables(all_tables)
    numeric_tables  = all_tables.select { |t| t.table_number.to_s =~ /^\d+$/ }
    columns         = detect_columns_from(numeric_tables)
    rows            = (numeric_tables.size.to_f / columns).ceil

    schedule_by_table = @schedules.group_by { |s| s.table_number.to_s.strip }

    tables_json = all_tables.map do |table|
      key             = table.table_number.to_s.strip
      table_schedules = schedule_by_table[key] || []

      {
        table_id:        table.id,
        table_number:    table.table_number,
        adjacent_tables: adjacent_by_id[table.id],
        meetings:        table_schedules.map { |s| build_meeting_info(s) },
        delegates:       participants_for(table_schedules)   # booker + target members ทั้งคู่
      }
    end

    {
      year:        @target_year,
      date:        @bkk_date,
      time:        @datetime.in_time_zone(TIMEZONE).iso8601,
      my_table:    find_my_schedule&.table_number,
      layout:      { type: "grid", rows: rows, columns: columns },
      tables:      tables_json,
      times_today: all_times_today,
      days:        all_days
    }
  end

  # ────────────────────────────────────────────
  # Query helpers
  # ────────────────────────────────────────────

  def schedule_exists_in_year?(year)
    Schedule
      .where("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}') = ?", year)
      .where("booker_id IS NOT NULL")
      .exists?
  end

  def load_schedules_at(datetime)
    base = Schedule.includes(
      :table,
      booker:   :company,
      delegate: :company,
      team:     [:delegates, :company]
    ).where("booker_id IS NOT NULL")

    slot_start = Schedule
      .where("start_at <= ? AND end_at > ?", datetime, datetime)
      .where("booker_id IS NOT NULL")
      .order(:start_at)
      .pick(:start_at)

    return base.none unless slot_start

    base.where(start_at: slot_start)
  end

  def times_today
    return [] unless @conference_date

    Schedule
      .where(conference_date_id: @conference_date.id)
      .where("booker_id IS NOT NULL")
      .order(:start_at)
      .pluck(:start_at)
      .map { |t| t.in_time_zone(TIMEZONE).iso8601 }
      .uniq
  end

  def conference_days
    return [] unless @conference
    @conference
      .conference_dates
      .joins(:schedules)
      .where("schedules.booker_id IS NOT NULL")
      .pluck(:on_date)
      .uniq
      .sort
  end

  def sorted_tables
    Table.order(
      Arel.sql("CASE WHEN table_number ~ '^[0-9]+$' THEN 0 ELSE 1 END, table_number::text")
    ).to_a
  end

  def parse_adjacent_tables(tables)
    tables.each_with_object({}) do |t, h|
      h[t.id] = YAML.safe_load(t.adjacent_tables || "--- []")
    rescue StandardError
      h[t.id] = []
    end
  end

  def detect_columns_from(numeric_tables)
    first_table = numeric_tables.find { |t| t.table_number.to_s == "1" }
    return 6 unless first_table

    near     = YAML.safe_load(first_table.adjacent_tables || "--- []")
    vertical = near.map(&:to_i).find { |n| n > 1 && (n - 1) > 1 }
    vertical ? vertical - 1 : 6
  rescue StandardError
    6
  end

  def find_my_schedule
    return nil unless @current_delegate

    did = @current_delegate.id
    tid = @current_delegate.team_id

    @schedules.find { |s| (s.booker_id == did || s.delegate_id == did) && s.table_number.present? } ||
      @schedules.find { |s| tid.present? && s.target_id == tid && s.table_number.present? } ||
      @schedules.find { |s| s.booker_id == did || s.delegate_id == did } ||
      @schedules.find { |s| tid.present? && s.target_id == tid }
  end

  def participants_for(table_schedules)
    # รวมทั้ง booker (side_a) และ target members (side_b) ของทุก meeting ที่โต๊ะนี้
    bookers = table_schedules.flat_map { |s| [s.booker, s.delegate].compact }
    targets = table_schedules.flat_map { |s| s.team&.delegates.to_a }

    (bookers + targets)
      .uniq(&:id)
      .sort_by(&:id)
      .map do |d|
        {
          id:         d.id,
          name:       d.name,
          title:      d.title&.strip,
          company:    d.company&.name || "N/A",
          avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(d.name)}"
        }
      end
  end

  def build_meeting_info(schedule)
    person_a = schedule.booker || schedule.delegate
    team     = schedule.team

    booker = if person_a
      {
        id:         person_a.id,
        name:       person_a.name,
        title:      person_a.title&.strip,
        company_id: person_a.company_id,
        company:    person_a.company&.name || "N/A",
        avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(person_a.name)}"
      }
    end

    target_team = if team
      members = team.delegates.map do |d|
        {
          id:         d.id,
          name:       d.name,
          title:      d.title&.strip,
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
      start_at:    schedule.start_at&.in_time_zone(TIMEZONE)&.iso8601,
      end_at:      schedule.end_at&.in_time_zone(TIMEZONE)&.iso8601,
      booker:      booker,       # คนจอง (นั่งที่โต๊ะนี้)
      target_team: target_team   # ทีมที่ถูกจอง (นั่งโต๊ะของตัวเอง)
    }
  end

  # ────────────────────────────────────────────
  # Param parsers
  # ────────────────────────────────────────────

  def parse_date_param(raw)
    return nil if raw.blank?
    Date.strptime(raw.to_s.strip, "%Y-%m-%d")
  rescue ArgumentError, TypeError
    nil
  end

  def parse_time_param(raw)
    return nil if raw.blank?
    cleaned = raw.to_s.strip
    cleaned =~ /\A\d{2}:\d{2}\z/ ? cleaned : nil
  end

  def parse_bangkok_datetime(year, date, time_str, fallback)
    Time.zone.parse("#{year}-#{date.strftime('%m-%d')} #{time_str}")
  rescue ArgumentError
    fallback
  end
end

