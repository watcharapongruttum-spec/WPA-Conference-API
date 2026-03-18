# app/models/table.rb
class Table < ApplicationRecord
  belongs_to :conference
  has_many :teams, dependent: :nullify
  has_many :schedules
  has_many :delegates

  TIMEZONE = "Asia/Bangkok"

  # ──────────────────────────────────────────────────────────────
  # Normalize table_number: "01" → "1", " 2 " → "2"
  # ──────────────────────────────────────────────────────────────
  def self.normalize_table_number(val)
    val.to_s.strip.gsub(/^0+/, "")
  end

  # ──────────────────────────────────────────────────────────────
  # Class methods
  # ──────────────────────────────────────────────────────────────

  def self.time_view(params:, current_delegate: nil)
    conference  = resolve_conference
    target_year = resolve_year(conference)
    datetime    = resolve_datetime(params, conference, target_year)
    schedules   = resolve_schedules(datetime, params, target_year)
    conf_date   = resolve_conference_date(datetime, conference, schedules)

    build_response(
      conference:       conference,
      target_year:      target_year,
      datetime:         datetime,
      schedules:        schedules,
      conf_date:        conf_date,
      current_delegate: current_delegate
    )
  end

  def self.resolve_conference
    Conference.find_by(is_current: true) ||
      Conference.order(conference_year: :desc).first
  end

  def self.resolve_year(conference)
    year = conference&.conference_year&.to_i || Date.today.year
    unless schedule_exists_in_year?(year)
      actual = Schedule
                 .where("booker_id IS NOT NULL")
                 .order(:start_at)
                 .pick(Arel.sql("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}')::int"))
      year = actual if actual
    end
    year
  end

  def self.schedule_exists_in_year?(year)
    Schedule
      .where("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}') = ?", year)
      .where("booker_id IS NOT NULL")
      .exists?
  end

  def self.resolve_datetime(params, conference, target_year)
    input_date      = parse_date_param(params[:date])
    input_time      = parse_time_param(params[:time])
    time_only_given = params[:date].blank? && params[:time].present?

    bkk_now    = Time.current.in_time_zone(TIMEZONE)
    input_date ||= bkk_now.to_date
    input_time ||= bkk_now.strftime("%H:%M")

    if time_only_given && conference
      first_day = conference
                    .conference_dates
                    .joins(:schedules)
                    .where("schedules.booker_id IS NOT NULL")
                    .order(:on_date)
                    .pick(:on_date)
      input_date = first_day if first_day
    end

    parse_bangkok_datetime(target_year, input_date, input_time, bkk_now)
  end

  # ──────────────────────────────────────────────────────────────
  # RESOLVE SCHEDULES
  #
  # กฎ:
  #   - ถ้าส่ง time มา → ตรวจสอบแบบเข้มงวด ต้องตรง slot เป๊ะ
  #     ถ้าเป็นเวลา break / event / ช่วงว่าง → คืน [] ทันที ไม่ snap
  #   - ถ้าไม่ส่ง time มา → ใช้ slot แรกของวันเป็น default
  #
  # ใช้ SQL หา schedule IDs ก่อน แล้วค่อย load ผ่าน ActiveRecord
  # เพื่อให้ได้ structure ครบเหมือนเดิมทุก field
  # ──────────────────────────────────────────────────────────────
  def self.resolve_schedules(datetime, params, target_year)
    conference = resolve_conference
    return [] unless conference

    tz       = TIMEZONE
    bkk_time = datetime.in_time_zone(tz)

    if params[:time].present?
      # ส่ง time มา → ต้อง match slot เป๊ะ (overlap 20 นาที)
      ids = fetch_schedule_ids_for_slot(bkk_time, conference, tz)
      return [] if ids.empty?

      load_schedules_by_ids(ids, target_year)
    else
      # ไม่ส่ง time → ใช้ slot แรกของวัน
      input_date = bkk_time.to_date
      ids = fetch_schedule_ids_for_day(input_date, conference, tz, target_year)
      return [] if ids.empty?

      load_schedules_by_ids(ids, target_year)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # SQL: หา schedule ids ที่ overlap กับช่วงเวลาที่กำหนด
  # overlap condition: start_at < end_ts AND (start_at + 20 min) > start_ts
  # ──────────────────────────────────────────────────────────────
  def self.fetch_schedule_ids_for_slot(bkk_time, conference, tz)
    start_ts = bkk_time.strftime("%Y-%m-%d %H:%M:%S")
    end_ts   = (bkk_time + 20.minutes).strftime("%Y-%m-%d %H:%M:%S")
    conf_id  = conference.id.to_i

    sql = <<~SQL
      WITH params AS (
        SELECT
          #{conf_id}::int         AS conference_id,
          timestamp '#{start_ts}' AS start_ts,
          timestamp '#{end_ts}'   AS end_ts
      ),
      matched AS (
        SELECT DISTINCT
          s.id                                                            AS schedule_id,
          (s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{tz}')           AS bkk_start
        FROM schedules s
        JOIN conference_dates cd ON s.conference_date_id = cd.id
        WHERE cd.conference_id = (SELECT conference_id FROM params)
          AND s.booker_id      IS NOT NULL
          AND s.table_number   IS NOT NULL
          AND TRIM(s.table_number) <> ''
          AND s.booker_id IN (SELECT id FROM delegates)
      )
      SELECT schedule_id
      FROM matched
      WHERE bkk_start < (SELECT end_ts   FROM params)
        AND (bkk_start + interval '20 minutes') > (SELECT start_ts FROM params)
      ORDER BY bkk_start;
    SQL

    ActiveRecord::Base.connection.exec_query(sql).rows.flatten.map(&:to_i)
  end

  # ──────────────────────────────────────────────────────────────
  # SQL: หา slot แรกของวัน แล้วดึง schedule ids ของ slot นั้น
  # ──────────────────────────────────────────────────────────────
  def self.fetch_schedule_ids_for_day(date, conference, tz, target_year)
    date_str = date.strftime("%Y-%m-%d")
    conf_id  = conference.id.to_i

    sql = <<~SQL
      WITH first_slot AS (
        SELECT MIN(s.start_at) AS slot_start
        FROM schedules s
        JOIN conference_dates cd ON s.conference_date_id = cd.id
        WHERE cd.conference_id = #{conf_id}
          AND s.booker_id      IS NOT NULL
          AND s.table_number   IS NOT NULL
          AND TRIM(s.table_number) <> ''
          AND s.booker_id IN (SELECT id FROM delegates)
          AND DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{tz}') = '#{date_str}'
          AND EXTRACT(YEAR FROM s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{tz}') = #{target_year.to_i}
      )
      SELECT s.id AS schedule_id
      FROM schedules s, first_slot
      WHERE s.start_at   = first_slot.slot_start
        AND s.booker_id  IS NOT NULL
        AND s.table_number IS NOT NULL
        AND TRIM(s.table_number) <> ''
        AND s.booker_id IN (SELECT id FROM delegates)
      ORDER BY s.id;
    SQL

    ActiveRecord::Base.connection.exec_query(sql).rows.flatten.map(&:to_i)
  end

  # ──────────────────────────────────────────────────────────────
  # โหลด schedules เต็มรูปแบบจาก ids ผ่าน ActiveRecord
  # → structure ครบ 100% เหมือนเดิม (booker_id, target_id, team, ฯลฯ)
  # ──────────────────────────────────────────────────────────────
  def self.load_schedules_by_ids(ids, target_year)
    schedules = Schedule
      .includes(booker: :company, delegate: :company, team: [:delegates, :company])
      .where(id: ids)
      .to_a

    schedules.map do |s|
      members = (s.team&.delegates || []).map do |d|
        { id: d.id, name: d.name.presence || "Unknown", title: d.title.presence&.strip || "" }
      end

      person = s.booker || s.delegate

      {
        id:           s.id,
        start_at:     s.start_at.in_time_zone(TIMEZONE),
        end_at:       s.end_at.in_time_zone(TIMEZONE),
        table_number: s.table_number,
        booker_id:    s.booker_id,
        delegate_id:  s.delegate_id,
        target_id:    s.target_id,
        booker: person ? {
          id:         person.id,
          name:       person.name.presence || "Unknown",
          title:      person.title.presence&.strip || "",
          company_id: person.company_id,
          company:    person.company&.name.presence || ""
        } : nil,
        delegate: nil,
        team: s.team ? {
          id:           s.team.id,
          name:         s.team.name.presence || "",
          country_code: s.team.country_code || "",
          company:      s.team.company&.name.presence || "",
          members:      members
        } : nil
      }
    end
  end

  def self.resolve_conference_date(datetime, conference, schedules)
    bkk_date = datetime.in_time_zone(TIMEZONE).to_date
    conference&.conference_dates&.find_by(on_date: bkk_date) ||
      begin
        first_schedule = schedules.first
        if first_schedule
          ConferenceDate.find_by(
            id: Schedule.where(id: first_schedule[:id]).pick(:conference_date_id)
          )
        end
      end
  end

  def self.build_response(conference:, target_year:, datetime:, schedules:, conf_date:, current_delegate:)
    bkk_date       = datetime.in_time_zone(TIMEZONE).to_date
    all_tables     = sorted_for_view
    adjacent_by_id = parse_adjacent_tables(all_tables)
    numeric_tables = all_tables.select { |t| t.table_number.to_s =~ /^\d+$/ }
    columns        = detect_columns_from(numeric_tables)
    rows           = (numeric_tables.size.to_f / columns).ceil

    # ── Pre-compute owner info ใน 1 query ─────────────────────
    # เจ้าของ Booth อาจปรากฏเป็น booker หรือ target ก็ได้
    # ต้อง resolve ทั้ง team_ids และ delegate_ids ของเจ้าของ
    # เพื่อใช้ใน to_time_view_json โดยไม่ต้อง query ซ้ำทุก Booth
    booth_tables    = all_tables.select { |t| t.table_number.to_s.match?(/\ABooth\s/i) }
    all_owner_teams = booth_tables.flat_map { |t| t.teams.map(&:id) }.uniq

    # query delegates ของ owner teams ทั้งหมดใน 1 ครั้ง
    owner_delegate_rows = all_owner_teams.any? ?
      Delegate.where(team_id: all_owner_teams).pluck(:id, :team_id) : []

    # delegates_by_team: { team_id => [delegate_id, ...] }
    delegates_by_team = owner_delegate_rows
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(did, tid), h|
        h[tid] << did
      end

    # owner_info: { normalized_table_number => { team_ids:, delegate_ids: } }
    owner_info = booth_tables.each_with_object({}) do |t, h|
      team_ids     = t.teams.map(&:id)
      delegate_ids = team_ids.flat_map { |tid| delegates_by_team[tid] }
      h[normalize_table_number(t.table_number)] = {
        team_ids:     team_ids,
        delegate_ids: delegate_ids
      }
    end

    schedule_by_table = schedules.group_by do |s|
      normalize_table_number(s[:table_number])
    end

    tables_json = all_tables
      .select { |t| schedule_by_table[normalize_table_number(t.table_number)]&.any? }
      .map { |t| t.to_time_view_json(schedule_by_table, owner_info) }

    {
      year:        target_year,
      date:        bkk_date,
      time:        datetime.in_time_zone(TIMEZONE).iso8601,
      my_table:    find_my_table(schedules, current_delegate),
      layout:      { type: "grid", rows: rows, columns: columns },
      tables:      tables_json,
      times_today: times_today_for(conf_date),
      days:        conference_days_for(conference)
    }
  end

  def self.sorted_for_view
    includes(:teams).order(
      Arel.sql("CASE WHEN table_number ~ '^[0-9]+$' THEN 0 ELSE 1 END, table_number::text")
    ).to_a
  end

  def self.parse_adjacent_tables(tables)
    tables.each_with_object({}) do |t, h|
      h[t.id] = YAML.safe_load(t.adjacent_tables || "--- []")
    rescue StandardError
      h[t.id] = []
    end
  end

  def self.detect_columns_from(numeric_tables)
    first_table = numeric_tables.find { |t| t.table_number.to_s == "1" }
    return 6 unless first_table

    near     = YAML.safe_load(first_table.adjacent_tables || "--- []")
    vertical = near.map(&:to_i).find { |n| n > 1 && (n - 1) > 1 }
    vertical ? vertical - 1 : 6
  rescue StandardError
    6
  end

  def self.find_my_table(schedules, current_delegate)
    return nil unless current_delegate

    did = current_delegate.id
    tid = current_delegate.team_id

    schedule =
      schedules.find { |s| (s[:booker_id] == did || s[:delegate_id] == did) && s[:table_number].present? } ||
      schedules.find { |s| tid.present? && s[:target_id] == tid && s[:table_number].present? } ||
      schedules.find { |s| s[:booker_id] == did || s[:delegate_id] == did } ||
      schedules.find { |s| tid.present? && s[:target_id] == tid }

    schedule&.dig(:table_number)
  end

  def self.times_today_for(conf_date)
    return [] unless conf_date

    Schedule
      .where(conference_date_id: conf_date.id)
      .where("booker_id IS NOT NULL")
      .order(:start_at)
      .pluck(:start_at)
      .map { |t| t.in_time_zone(TIMEZONE).iso8601 }
      .uniq
  end

  def self.conference_days_for(conference)
    return [] unless conference

    conference
      .conference_dates
      .joins(:schedules)
      .where("schedules.booker_id IS NOT NULL")
      .pluck(:on_date)
      .uniq
      .sort
  end

  def self.parse_date_param(raw)
    return nil if raw.blank?
    Date.strptime(raw.to_s.strip, "%Y-%m-%d")
  rescue ArgumentError, TypeError
    nil
  end

  def self.parse_time_param(raw)
    return nil if raw.blank?
    cleaned = raw.to_s.strip
    return nil unless cleaned =~ /\A\d{1,2}:\d{2}\z/
    cleaned.rjust(5, "0")
  end

  def self.parse_bangkok_datetime(year, date, time_str, fallback)
    ActiveSupport::TimeZone[TIMEZONE].parse("#{year}-#{date.strftime('%m-%d')} #{time_str}")
  rescue ArgumentError
    fallback
  end

  # ──────────────────────────────────────────────────────────────
  # Instance methods
  # ──────────────────────────────────────────────────────────────

  def to_time_view_json(schedule_by_table, owner_info)
    key             = Table.normalize_table_number(table_number)
    table_schedules = schedule_by_table[key] || []

    adjacent = begin
      YAML.safe_load(adjacent_tables || "--- []")
    rescue StandardError
      []
    end

    display_schedules = if table_number.to_s.match?(/\ABooth\s/i)
      info         = owner_info[key] || { team_ids: [], delegate_ids: [] }
      team_ids     = info[:team_ids]
      delegate_ids = info[:delegate_ids]

      if team_ids.any?
        # ══════════════════════════════════════════════════════
        # เจ้าของ Booth ปรากฏใน schedule ได้ 2 แบบ:
        #
        #   แบบ A: เจ้าของนั่งรับ visitor
        #          target_id = owner team, booker = visitor
        #          → แสดง schedule นี้เป็นหลัก
        #
        #   แบบ B: เจ้าของเป็น booker ไปหา visitor ที่ Booth ตัวเอง
        #          booker_id = owner delegate, target = visitor's team
        #          → แสดง schedule นี้ถ้าไม่มีแบบ A
        #
        # ถ้าไม่พบ schedule ของ owner เลยใน slot นี้ → คืน []
        # ไม่ fallback ไปแสดง schedule ของ visitor เป็นเจ้าของผิด
        # ══════════════════════════════════════════════════════
        chosen =
          table_schedules.find { |s| team_ids.include?(s[:target_id]) } ||
          table_schedules.find { |s| delegate_ids.include?(s[:booker_id]) }

        chosen ? [chosen] : []
      else
        # ไม่มี owner team ผูกไว้ → fallback min id
        chosen = table_schedules.min_by { |s| s[:id] }
        chosen ? [chosen] : []
      end
    else
      table_schedules
    end

    {
      table_id:        id,
      table_number:    table_number,
      adjacent_tables: adjacent,
      meetings:        display_schedules.map { |s| build_meeting_json(s) },
      delegates:       build_delegates_json(display_schedules)
    }
  end

  private

  def build_meeting_json(schedule)
    person_a = schedule[:booker] || schedule[:delegate]
    team     = schedule[:team]

    booker_json = if person_a
      {
        id:         person_a[:id],
        name:       person_a[:name],
        title:      person_a[:title],
        company_id: person_a[:company_id],
        company:    person_a[:company],
        avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(person_a[:name].to_s)}"
      }
    end

    target_team_json = if team
      {
        team_id:      team[:id],
        team_name:    team[:name],
        country_code: team[:country_code],
        company:      team[:company],
        members:      team[:members].map do |m|
          m.merge(avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(m[:name].to_s)}")
        end,
        member_count: team[:members].size
      }
    end

    {
      schedule_id: schedule[:id],
      start_at:    schedule[:start_at]&.iso8601,
      end_at:      schedule[:end_at]&.iso8601,
      booker:      booker_json,
      target_team: target_team_json
    }
  end

  def build_delegates_json(table_schedules)
    bookers = table_schedules.filter_map { |s| s[:booker] || s[:delegate] }
    members = table_schedules.flat_map { |s| s.dig(:team, :members) || [] }

    (bookers + members)
      .uniq { |d| d[:id] }
      .sort_by { |d| d[:id] }
      .map do |d|
        {
          id:         d[:id],
          name:       d[:name],
          title:      d[:title],
          company:    d[:company] || "",
          avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(d[:name].to_s)}"
        }
      end
  end
end