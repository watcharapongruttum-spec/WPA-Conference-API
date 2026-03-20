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
  # RESOLVE SCHEDULES
  # ──────────────────────────────────────────────────────────────
  def self.resolve_schedules(datetime, params, target_year)
    conference = resolve_conference
    return [] unless conference

    bkk_time = datetime.in_time_zone(TIMEZONE)

    if params[:time].present?
      start_ts = bkk_time
      end_ts   = bkk_time + 20.minutes
    else
      first_slot = find_first_slot(bkk_time.to_date, conference, target_year)
      return [] unless first_slot

      start_ts = first_slot
      end_ts   = first_slot + 20.minutes
    end

    fetch_time_view_rows(conference.id, start_ts, end_ts)
  end

  # ──────────────────────────────────────────────────────────────
  # หา slot แรกของวัน
  # ──────────────────────────────────────────────────────────────
  def self.find_first_slot(date, conference, target_year)
    sql = <<~SQL
      SELECT MIN(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') AS first_slot
      FROM schedules s
      JOIN conference_dates cd ON s.conference_date_id = cd.id
      WHERE cd.conference_id = $1
        AND s.booker_id IS NOT NULL
        AND s.table_number IS NOT NULL
        AND TRIM(s.table_number) <> ''
        AND DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') = $2
        AND EXTRACT(YEAR FROM s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') = $3
    SQL

    result = connection.exec_query(
      sql, "find_first_slot",
      [conference.id, date.strftime("%Y-%m-%d"), target_year]
    ).first

    return nil unless result&.dig("first_slot")

    raw_time = result["first_slot"]
    bkk_str  = raw_time.strftime("%Y-%m-%d %H:%M:%S")
    ActiveSupport::TimeZone[TIMEZONE].parse(bkk_str)
  rescue StandardError
    nil
  end

  # ──────────────────────────────────────────────────────────────
  # fetch_time_view_rows
  # FIX: ลบ LEFT JOIN delegates d (ที่ทำให้ delegate ข้ามโต๊ะ) ออก
  #      ลบ json_agg delegates ออก — ใช้เฉพาะ members จาก target_team แทน
  # ──────────────────────────────────────────────────────────────
  def self.fetch_time_view_rows(conference_id, start_ts, end_ts)
    utc_start = start_ts.utc.strftime("%Y-%m-%d %H:%M:%S")
    utc_end   = end_ts.utc.strftime("%Y-%m-%d %H:%M:%S")

    sql = <<~SQL
      WITH params AS (
        SELECT
          $1::int       AS conference_id,
          $2::timestamp AS start_ts,
          $3::timestamp AS end_ts
      ),
      slot_schedules AS (
        SELECT DISTINCT s.id, s.start_at, s.table_number, s.booker_id, s.target_id
        FROM schedules s
        JOIN conference_dates cd ON s.conference_date_id = cd.id
        WHERE cd.conference_id = (SELECT conference_id FROM params)
          AND s.table_number IS NOT NULL
          AND TRIM(s.table_number) <> ''
          AND s.booker_id IS NOT NULL
          AND s.start_at <  (SELECT end_ts   FROM params)
          AND (s.start_at + interval '20 minutes') > (SELECT start_ts FROM params)
      )
      SELECT
        to_char(
          ss.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
          'YYYY-MM-DD"T"HH24:MI:SS+07:00'
        ) AS start_at,
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
        )) AS meetings
      FROM slot_schedules ss
      LEFT JOIN delegates  d_b ON d_b.id  = ss.booker_id
      LEFT JOIN companies  c_b ON c_b.id  = d_b.company_id
      LEFT JOIN teams      t   ON t.id    = ss.target_id
      LEFT JOIN companies  c_t ON c_t.id  = t.company_id
      GROUP BY ss.start_at, ss.table_number
      ORDER BY ss.start_at
    SQL

    tz = ActiveSupport::TimeZone[TIMEZONE]

    connection.exec_query(
      sql, "fetch_time_view_rows",
      [conference_id.to_i, utc_start, utc_end]
    ).flat_map do |row|
      meetings     = parse_json_agg(row["meetings"])
      start_at_str = row["start_at"].to_s
      start_at     = Time.iso8601(start_at_str).in_time_zone(tz)
      end_at_str   = (start_at + 20.minutes).strftime("%Y-%m-%dT%H:%M:%S+07:00")

      meetings.map do |m|
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
          start_at_str: start_at_str,
          end_at_str:   end_at_str,
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

    owner_delegate_full = all_owner_teams.any? ?
      Delegate.where(team_id: all_owner_teams).pluck(:id, :team_id, :company_id) : []

    delegates_by_team = owner_delegate_full
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(did, tid, _cid), h|
        h[tid] << did
      end

    delegate_company_by_team = owner_delegate_full
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(_did, tid, cid), h|
        h[tid] << cid if cid
      end

    all_company_ids = (
      booth_tables.flat_map { |t| t.teams.map(&:company_id) } +
      owner_delegate_full.map { |(_did, _tid, cid)| cid }
    ).compact.uniq

    owner_companies_map = Company.where(id: all_company_ids).pluck(:id, :name).to_h

    owner_info = booth_tables.each_with_object({}) do |t, h|
      team_ids     = t.teams.map(&:id)
      delegate_ids = team_ids.flat_map { |tid| delegates_by_team[tid] }

      companies = t.teams.flat_map do |team|
        if team.company_id
          [owner_companies_map[team.company_id]].compact
        else
          delegate_company_by_team[team.id].filter_map { |cid| owner_companies_map[cid] }
        end
      end.uniq

      h[normalize_table_number(t.table_number)] = {
        team_ids:     team_ids,
        delegate_ids: delegate_ids,
        companies:    companies,
        owner_teams:  t.teams.map(&:name)
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

    meeting_times = Schedule
      .where(conference_date_id: conf_date.id)
      .where("booker_id IS NOT NULL")
      .order(:start_at)
      .pluck(:start_at)
      .map { |t| t.in_time_zone(TIMEZONE).iso8601 }

    activity_times = ConferenceSchedule
      .where(conference_date_id: conf_date.id)
      .order(:start_at)
      .pluck(:start_at)
      .map { |t| t.in_time_zone(TIMEZONE).iso8601 }

    (meeting_times + activity_times).uniq.sort
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

    occupied_schedules = table_schedules.select { |s| s[:booker].present? }

    is_booth       = table_number.to_s.match?(/\ABooth\s/i)
    info           = owner_info[key] || { team_ids: [], delegate_ids: [], companies: [] }
    owner_team_ids = is_booth ? info[:team_ids] : []

    display_schedules = if is_booth && owner_team_ids.any?
      occupied_schedules.filter do |s|
        owner_team_ids.include?(s[:target_id]) || owner_team_ids.include?(s[:booker_id])
      end
    else
      occupied_schedules
    end

    result = {
      table_id:        id,
      table_number:    table_number,
      adjacent_tables: adjacent,
      meetings:        display_schedules.map { |s| build_meeting_json(s, owner_team_ids, info[:companies]) },
      delegates:       build_delegates_json(display_schedules)
    }

    if is_booth
      result[:booth_owner] = {
        team_ids:    owner_team_ids,
        companies:   info[:companies],
        owner_teams: info[:owner_teams] || []
      }
    end

    result
  end

  private

  def build_meeting_json(schedule, owner_team_ids = [], owner_companies = [])
    person_a = schedule[:booker]
    team     = schedule[:team]

    booker_is_owner = owner_team_ids.include?(schedule[:booker_id])
    target_is_owner = owner_team_ids.include?(schedule[:target_id])

    meeting_role = if owner_team_ids.any?
      if booker_is_owner && target_is_owner
        "owner_internal"
      elsif booker_is_owner
        "owner_hosting"
      elsif target_is_owner
        "owner_as_target"
      end
    end

    owner_company = if booker_is_owner
      owner_companies.join(" & ")
    elsif target_is_owner
      team&.dig(:company).presence || owner_companies.join(" & ")
    end

    guest_company = if booker_is_owner
      team&.dig(:company)
    elsif target_is_owner
      person_a&.dig(:company)
    end

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

    meeting = {
      schedule_id: schedule[:id],
      start_at:    schedule[:start_at_str],
      end_at:      schedule[:end_at_str],
      booker:      booker_json,
      target_team: target_team_json
    }

    if meeting_role
      meeting[:meeting_role]    = meeting_role
      meeting[:booker_is_owner] = booker_is_owner
      meeting[:target_is_owner] = target_is_owner
      meeting[:owner_company]   = owner_company
      meeting[:guest_company]   = guest_company
    end

    meeting
  end

  # FIX: ลบ booker_members ออก — ใช้เฉพาะ booker + target team members
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