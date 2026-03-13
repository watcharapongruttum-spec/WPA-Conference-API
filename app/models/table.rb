# app/models/table.rb
class Table < ApplicationRecord
  belongs_to :conference
  has_many :teams, dependent: :nullify
  has_many :schedules
  has_many :delegates

  TIMEZONE = "Asia/Bangkok"

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

  def self.resolve_schedules(datetime, params, target_year)
    user_selected = params[:date].present? && params[:time].present?
    schedules     = load_schedules_at(datetime)
    input_date    = datetime.in_time_zone(TIMEZONE).to_date

    if schedules.empty? && !user_selected
      first_of_day = Schedule
        .where("DATE(start_at AT TIME ZONE '#{TIMEZONE}') = ?", input_date)
        .where("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}') = ?", target_year)
        .where("booker_id IS NOT NULL")
        .order(:start_at)
        .pick(:start_at)
      schedules = load_schedules_at(first_of_day) if first_of_day
    end

    if schedules.empty? && !user_selected
      first_of_year = Schedule
        .where("EXTRACT(YEAR FROM start_at AT TIME ZONE '#{TIMEZONE}') = ?", target_year)
        .where("booker_id IS NOT NULL")
        .order(:start_at)
        .pick(:start_at)
      schedules = load_schedules_at(first_of_year) if first_of_year
    end

    schedules
  end

  def self.load_schedules_at(datetime)
    base = Schedule.includes(
      :table,
      booker:   :company,
      delegate: :company,
      team:     [:delegates, :company]
    ).where("booker_id IS NOT NULL")
     .where("table_number IS NOT NULL AND table_number != ''")
     .where("booker_id IN (?)", Delegate.select(:id))

    slot_start = Schedule
      .where("start_at <= ? AND end_at > ?", datetime, datetime)
      .where("booker_id IS NOT NULL")
      .order(:start_at)
      .pick(:start_at)

    return base.none unless slot_start

    base.where(start_at: slot_start)
  end

  def self.resolve_conference_date(datetime, conference, schedules)
    bkk_date = datetime.in_time_zone(TIMEZONE).to_date
    conference&.conference_dates&.find_by(on_date: bkk_date) ||
      schedules.first&.conference_date
  end

  def self.build_response(conference:, target_year:, datetime:, schedules:, conf_date:, current_delegate:)
    bkk_date          = datetime.in_time_zone(TIMEZONE).to_date
    all_tables        = sorted_for_view
    adjacent_by_id    = parse_adjacent_tables(all_tables)
    numeric_tables    = all_tables.select { |t| t.table_number.to_s =~ /^\d+$/ }
    columns           = detect_columns_from(numeric_tables)
    rows              = (numeric_tables.size.to_f / columns).ceil
    schedule_by_table = schedules.group_by { |s| s.table_number.to_s.strip }

    tables_json = all_tables
      .select { |t| schedule_by_table[t.table_number.to_s.strip]&.any? }
      .map { |t| t.to_time_view_json(schedule_by_table, adjacent_by_id) }

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
    order(
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
      schedules.find { |s| (s.booker_id == did || s.delegate_id == did) && s.table_number.present? } ||
      schedules.find { |s| tid.present? && s.target_id == tid && s.table_number.present? } ||
      schedules.find { |s| s.booker_id == did || s.delegate_id == did } ||
      schedules.find { |s| tid.present? && s.target_id == tid }

    schedule&.table_number
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
    cleaned =~ /\A\d{2}:\d{2}\z/ ? cleaned : nil
  end

  def self.parse_bangkok_datetime(year, date, time_str, fallback)
    Time.zone.parse("#{year}-#{date.strftime('%m-%d')} #{time_str}")
  rescue ArgumentError
    fallback
  end

  # ──────────────────────────────────────────────────────────────
  # Instance methods
  # ──────────────────────────────────────────────────────────────

  def to_time_view_json(schedule_by_table, adjacent_by_id)
    key             = table_number.to_s.strip
    table_schedules = schedule_by_table[key] || []

    {
      table_id:        id,
      table_number:    table_number,
      adjacent_tables: adjacent_by_id[id] || [],
      meetings:        table_schedules.map { |s| build_meeting_json(s) },
      delegates:       build_delegates_json(table_schedules)
    }
  end

  private

  def build_meeting_json(schedule)
    person_a = schedule.booker || schedule.delegate
    team     = schedule.team

    booker_json = if person_a
      {
        id:         person_a.id,
        name:       person_a.name.presence || "Unknown",
        title:      person_a.title.presence&.strip || "",
        company_id: person_a.company_id,
        company:    person_a.company&.name.presence || "",
        avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(person_a.name.to_s)}"
      }
    end

    target_team_json = if team
      members = team.delegates.map do |d|
        {
          id:         d.id,
          name:       d.name.presence || "Unknown",
          title:      d.title.presence&.strip || "",
          avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(d.name.to_s)}"
        }
      end
      {
        team_id:      team.id,
        team_name:    team.name.presence || "",
        country_code: team.country_code || "",
        company:      team.company&.name.presence || "",
        members:      members,
        member_count: members.size
      }
    end

    {
      schedule_id: schedule.id,
      start_at:    schedule.start_at&.in_time_zone(TIMEZONE)&.iso8601,
      end_at:      schedule.end_at&.in_time_zone(TIMEZONE)&.iso8601,
      booker:      booker_json,
      target_team: target_team_json
    }
  end

  def build_delegates_json(table_schedules)
    bookers = table_schedules.flat_map { |s| [s.booker, s.delegate].compact }
    targets = table_schedules.flat_map { |s| s.team&.delegates.to_a }

    (bookers + targets)
      .uniq(&:id)
      .sort_by(&:id)
      .map do |d|
        {
          id:         d.id,
          name:       d.name.presence || "Unknown",
          title:      d.title.presence&.strip || "",
          company:    d.company&.name.presence || "",
          avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(d.name.to_s)}"
        }
      end
  end
end