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

    selected_date = datetime.in_time_zone(TIMEZONE).to_date

    build_response(
      selected_date:    selected_date,
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
                 .pick(Arel.sql("EXTRACT(YEAR FROM start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}')::int"))
      year = actual if actual
    end
    year
  end

  def self.schedule_exists_in_year?(year)
    Schedule
      .where("EXTRACT(YEAR FROM start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}') = ?", year)
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
  # RESOLVE SCHEDULES  — ใช้ SQL ใหม่ (overlap-based)
  # ──────────────────────────────────────────────────────────────
  def self.resolve_schedules(datetime, params, target_year)
    conference = resolve_conference
    return [] unless conference

    bkk_time = datetime.in_time_zone(TIMEZONE)

    if params[:time].present?
      # ── time mode: slot ที่ระบุ ─────────────────────────────────
      start_ts = bkk_time
      end_ts   = bkk_time + 20.minutes
    else
      # ── day mode: หา slot แรกของวัน แล้ว query slot นั้น ────────
      first_slot = find_first_slot(bkk_time.to_date, conference, target_year)
      return [] unless first_slot

      start_ts = first_slot
      end_ts   = first_slot + 20.minutes
    end

    fetch_time_view_rows(conference.id, start_ts, end_ts)
  end

  # ──────────────────────────────────────────────────────────────
  # หา slot แรกของวัน (ใช้สำหรับ day mode)
  # ──────────────────────────────────────────────────────────────
  def self.find_first_slot(date, conference, target_year)
    sql = <<~SQL
      SELECT MIN(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}') AS first_slot
      FROM schedules s
      JOIN conference_dates cd ON s.conference_date_id = cd.id
      WHERE cd.conference_id = #{conference.id.to_i}
        AND s.booker_id IS NOT NULL
        AND s.table_number IS NOT NULL
        AND TRIM(s.table_number) <> ''
        AND DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}') = '#{date.strftime("%Y-%m-%d")}'
        AND EXTRACT(YEAR FROM s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}') = #{target_year.to_i}
    SQL

    result = connection.exec_query(sql).first
    return nil unless result&.dig("first_slot")

    ActiveSupport::TimeZone[TIMEZONE].parse(result["first_slot"].to_s)
  rescue StandardError
    nil
  end

  # ──────────────────────────────────────────────────────────────
  # SQL ใหม่ — GROUP BY table, คืน meetings + delegates เป็น JSON
  # ──────────────────────────────────────────────────────────────
  def self.fetch_time_view_rows(conference_id, start_ts, end_ts)
    bkk_start = start_ts.in_time_zone(TIMEZONE).strftime("%Y-%m-%d %H:%M:%S")
    bkk_end   = end_ts.in_time_zone(TIMEZONE).strftime("%Y-%m-%d %H:%M:%S")

    sql = <<~SQL
      WITH params AS (
        SELECT
          #{conference_id.to_i}::int AS conference_id,
          '#{bkk_start}'::timestamp AS start_ts,
          '#{bkk_end}'::timestamp   AS end_ts
      ),
      slot_schedules AS (
        SELECT DISTINCT s.id, s.start_at, s.table_number, s.booker_id, s.target_id
        FROM schedules s
        JOIN conference_dates cd ON s.conference_date_id = cd.id
        WHERE cd.conference_id = (SELECT conference_id FROM params)
          AND s.table_number IS NOT NULL
          AND TRIM(s.table_number) <> ''
          AND (s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}') <  (SELECT end_ts FROM params)
          AND ((s.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}') + interval '20 minutes') > (SELECT start_ts FROM params)
      )
      SELECT
        (ss.start_at AT TIME ZONE 'UTC' AT TIME ZONE '#{TIMEZONE}') AS start_at,
        ss.table_number AS "table",
        json_agg(DISTINCT jsonb_build_object(
          'schedule_id',  ss.id,
          'booker', CASE WHEN d_b.id IS NOT NULL THEN jsonb_build_object(
            'id',         d_b.id,
            'name',       d_b.name,
            'title',      COALESCE(d_b.title, ''),
            'company_id', d_b.company_id,
            'company',    COALESCE(c_b.name, '')
          ) ELSE NULL END,
          'target_team', CASE WHEN t.id IS NOT NULL THEN jsonb_build_object(
            'team_id',      t.id,
            'team_name',    t.name,
            'country_code', COALESCE(c_t.country, ''),
            'company',      COALESCE(c_t.name, ''),
            'members', (
              SELECT json_agg(jsonb_build_object(
                'id',    dm.id,
                'name',  dm.name,
                'title', COALESCE(dm.title, '')
              ) ORDER BY dm.id)
              FROM delegates dm WHERE dm.team_id = t.id
            )
          ) ELSE NULL END
        )) AS meetings,
        json_agg(DISTINCT jsonb_build_object(
          'id',    d.id,
          'name',  d.name,
          'title', COALESCE(d.title, '')
        )) FILTER (WHERE d.id IS NOT NULL) AS delegates
      FROM slot_schedules ss
      LEFT JOIN delegates  d_b ON d_b.id  = ss.booker_id
      LEFT JOIN companies  c_b ON c_b.id  = d_b.company_id
      LEFT JOIN teams      t   ON t.id    = ss.target_id
      LEFT JOIN companies  c_t ON c_t.id  = t.company_id
      LEFT JOIN delegates  d   ON d.team_id IN (ss.target_id, (SELECT team_id FROM delegates WHERE id = ss.booker_id LIMIT 1))
      GROUP BY ss.start_at, ss.table_number
      ORDER BY ss.start_at
    SQL

    tz = ActiveSupport::TimeZone[TIMEZONE]

    connection.exec_query(sql).flat_map do |row|
      meetings = parse_json_agg(row["meetings"])
      start_at = tz.parse(row["start_at"].to_s)

      meetings.map do |m|
        # nested hashes จาก json_agg ยังเป็น string keys → deep symbolize
        booker_raw = m[:booker].is_a?(Hash) ? m[:booker].transform_keys(&:to_sym) : nil
        team_raw   = m[:target_team].is_a?(Hash) ? m[:target_team].transform_keys(&:to_sym) : nil

        booker = booker_raw&.dig(:id) ? booker_raw : nil

        team = if team_raw&.dig(:team_id)
          members = Array(team_raw[:members]).map do |mem|
            mem.is_a?(Hash) ? mem.transform_keys(&:to_sym) : mem
          end
          {
            id:           team_raw[:team_id],
            name:         team_raw[:team_name].to_s,
            country_code: team_raw[:country_code].to_s,
            company:      team_raw[:company].to_s,
            members:      members
          }
        end

        {
          id:           m[:schedule_id],
          start_at:     start_at,
          end_at:       start_at + 20.minutes,
          table_number: row["table"],
          booker_id:    booker&.dig(:id),
          target_id:    team&.dig(:id),
          booker:       booker,
          team:         team
        }
      end
    end
  rescue StandardError => e
    Rails.logger.error("[Table.fetch_time_view_rows] #{e.message}")
    []
  end

  # ──────────────────────────────────────────────────────────────
  # (ส่วนล่างนี้ไม่เปลี่ยน)
  # ──────────────────────────────────────────────────────────────

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

  def self.build_response(selected_date:, conference:, target_year:, datetime:, schedules:, conf_date:, current_delegate:)
    bkk_date       = datetime.in_time_zone(TIMEZONE).to_date
    all_tables     = sorted_for_view
    adjacent_by_id = parse_adjacent_tables(all_tables)
    numeric_tables = all_tables.select { |t| t.table_number.to_s =~ /^\d+$/ }
    columns        = detect_columns_from(numeric_tables)
    rows           = (numeric_tables.size.to_f / columns).ceil

    booth_tables    = all_tables.select { |t| t.table_number.to_s.match?(/\ABooth\s/i) }
    all_owner_teams = booth_tables.flat_map { |t| t.teams.map(&:id) }.uniq

    owner_delegate_rows = all_owner_teams.any? ?
      Delegate.where(team_id: all_owner_teams).pluck(:id, :team_id) : []

    delegates_by_team = owner_delegate_rows
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(did, tid), h|
        h[tid] << did
      end

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
      .select { |t| schedule_by_table[normalize_table_number(t.table_number)]&.any? { |s| s[:booker].present? } }
      .map { |t| t.to_time_view_json(schedule_by_table, owner_info) }

    {
      year:        target_year,
      date:        selected_date.strftime("%Y-%m-%d"),
      time:        datetime.in_time_zone(TIMEZONE).iso8601,
      my_table:    find_my_table(current_delegate, datetime),
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

  def self.find_my_table(current_delegate, datetime)
    return nil unless current_delegate
    return nil unless datetime

    bkk_time    = datetime.in_time_zone(TIMEZONE)
    filter_date = bkk_time.to_date
    reservation = Reservation.find_by(id: current_delegate.reservation_id)
    conference_id = reservation&.conference_id
    return nil unless conference_id

    rows = Schedule.timeline_rows(
      conference_id: conference_id,
      filter_date:   filter_date,
      delegate_id:   current_delegate.id,
      label:         "find_my_table"
    )

    record = rows.find do |row|
      row["type"] == "meeting" &&
        row["start_at"].to_s.include?(bkk_time.strftime("%H:%M"))
    end

    return nil unless record

    table_number = record["table_number"]
    return nil if table_number.blank?

    table_number.to_s.strip
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
  # PRIVATE CLASS METHODS
  # ──────────────────────────────────────────────────────────────
  class << self
    private

    def parse_json_agg(value)
      return [] if value.nil?
      parsed = value.is_a?(String) ? JSON.parse(value) : value
      Array(parsed).map { |item| item.transform_keys(&:to_sym) }
    rescue JSON::ParserError
      []
    end
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

    # ถ้า booker = null → ถือว่าโต๊ะว่าง (delegate ถูกลบออกจากระบบแล้ว)
    occupied_schedules = table_schedules.select { |s| s[:booker].present? }

    # เลือก slot ที่จะแสดง (Booth = เลือก slot ที่ owner เป็นเจ้าของ)
    display_schedules = if table_number.to_s.match?(/\ABooth\s/i)
      info         = owner_info[key] || { team_ids: [], delegate_ids: [] }
      team_ids     = info[:team_ids]
      delegate_ids = info[:delegate_ids]

      if team_ids.any?
        chosen =
          occupied_schedules.find { |s| team_ids.include?(s[:target_id]) } ||
          occupied_schedules.find { |s| delegate_ids.include?(s[:booker_id]) }
        chosen ? [chosen] : []
      else
        occupied_schedules.first ? [occupied_schedules.first] : []
      end
    else
      occupied_schedules
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
    person_a = schedule[:booker]
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
    bookers = table_schedules.filter_map { |s| s[:booker] }
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