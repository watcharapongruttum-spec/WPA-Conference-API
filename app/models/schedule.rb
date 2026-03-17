class Schedule < ApplicationRecord
  # ===============================
  # RELATIONS
  # ===============================
  belongs_to :conference_date
  belongs_to :booker, class_name: "Delegate", foreign_key: :booker_id, optional: true
  belongs_to :table, optional: true
  belongs_to :delegate, optional: true
  belongs_to :team, foreign_key: :target_id, optional: true

  has_many :leave_forms


  has_one :latest_leave_form,
          -> { order(created_at: :desc) },
          class_name: "LeaveForm"

  validate :table_not_double_booked, if: -> { table_number.present? && start_at.present? }

  # ===============================
  # DEFAULT INCLUDE
  # ===============================
  scope :with_full_data, lambda {
    includes(
      :conference_date,
      latest_leave_form: :leave_type,
      team: :delegates,
      booker: :company
    )
  }

  # ===============================
  # BASIC SCOPES
  # ===============================
  scope :mine, lambda { |delegate_id|
    delegate = Delegate.find_by(id: delegate_id)
    team_id = delegate&.team_id

    if team_id
      where("booker_id = :did OR target_id = :tid", did: delegate_id, tid: team_id)
    else
      where(booker_id: delegate_id)
    end
  }

  scope :not_mine, lambda { |delegate_id|
    delegate = Delegate.find_by(id: delegate_id)
    team_id = delegate&.team_id

    if team_id
      where.not(
        "schedules.booker_id = :did OR schedules.target_id = :tid",
        did: delegate_id,
        tid: team_id
      )
    else
      where.not(booker_id: delegate_id)
    end
  }

  scope :by_date, ->(conference_date_id) { where(conference_date_id: conference_date_id) }

  scope :sorted, lambda { |sort_by = nil, sort_dir = nil|
    allowed = %w[start_at end_at created_at table_number]
    column  = allowed.include?(sort_by) ? sort_by : "start_at"
    dir     = sort_dir == "desc" ? "desc" : "asc"
    order("#{column} #{dir}")
  }

  scope :search_name, lambda { |keyword|
    left_joins(:booker).where(
      "bookers_delegates.name ILIKE :k",
      k: "%#{keyword}%"
    )
  }

  # ===============================
  # YEARS / DATES
  # ===============================
  def self.years_of(delegate_id)
    joins(conference_date: :conference)
      .mine(delegate_id)
      .pluck("conferences.conference_year")
      .uniq
      .sort
  end

  def self.available_dates_of(conference)
    conference.conference_dates.order(:on_date).pluck(:on_date)
  end

  def self.resolve_date(params_date, delegate_id, conference, available_dates)
    if params_date.present?
      begin
        return Date.parse(params_date)
      rescue
        nil
      end
    end

    first = joins(:conference_date)
            .where(conference_dates: { conference_id: conference.id })
            .mine(delegate_id)
            .order("conference_dates.on_date ASC")
            .first

    first&.conference_date&.on_date || available_dates.first
  end

  def self.format_time(time)
    TimeFormatter.format(time)
  end

  # =====================================================
  # SLOT RESOLVER
  # =====================================================
  def self.resolve_time_slot(conference_date_id:, date:, time:)
    return nil unless time.present?

    selected_time =
      begin
        Time.zone.parse("#{date} #{time}")
      rescue
        nil
      end

    return nil unless selected_time

    where(conference_date_id: conference_date_id)
      .where("start_at <= ? AND end_at > ?", selected_time, selected_time)
      .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
      .order(:start_at)
      .first
  end

  # =====================================================
  # CENTRAL TIMELINE BUILDER
  # =====================================================
  def self.build_timeline_for(delegate:, params:)
    years = years_of(delegate.id)

    year = params[:year].presence || "2025"
    conference = Conference.find_by(conference_year: year)
    return { error: :conference_not_found, years: years } unless conference

    available_dates = available_dates_of(conference)
    selected_date = resolve_date(params[:date], delegate.id, conference, available_dates)
    return { error: :no_dates } unless selected_date

    conference_date = conference.conference_dates.find_by(on_date: selected_date)
    return { error: :date_not_found } unless conference_date

    slot = resolve_time_slot(
      conference_date_id: conference_date.id,
      date: selected_date,
      time: params[:time]
    )

    personal_scope = with_full_data
                    .mine(delegate.id)
                    .by_date(conference_date.id)
                    .where(
                      "booker_id IS NULL OR booker_id IN (?)",
                      Delegate.select(:id)
                    )

    personal_scope = personal_scope.where(start_at: slot.start_at) if slot

    all_personal = personal_scope.sorted.to_a

    personal =
      all_personal
      .group_by(&:start_at)
      .map do |_time, meetings|
        meetings.find { |m| m.booker_id == delegate.id } ||
        meetings.find { |m| m.table_number.present? } ||
        meetings.first
      end

    global_scope = ConferenceSchedule
                   .by_date(conference_date.id)
                   .only_events

    global_scope = global_scope.where(start_at: slot.start_at) if slot

    global = global_scope.sorted.to_a

    merged = []

    global.each do |g|
      merged << {
        type: "event",
        id: g.id,
        title: g.title,
        start_at: format_time(g.start_at),
        end_at: format_time(g.end_at),
        raw_start: g.start_at
      }
    end

    personal.each do |s|
      merged << {
        type: "meeting",
        serializer: s,
        start_at: format_time(s.start_at),
        end_at: format_time(s.end_at),
        raw_start: s.start_at
      }
    end

    if slot
      all_slots = [[slot.start_at, slot.end_at]]
    else
      all_slots = Schedule
                    .where(conference_date_id: conference_date.id)
                    .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
                    .distinct
                    .pluck(:start_at, :end_at)
    end

    personal_times = personal.map(&:start_at).to_set
    event_times = global.map(&:start_at).to_set

    all_slots.each do |start_at, end_at|
      next if personal_times.include?(start_at)
      next if event_times.include?(start_at)

      merged << {
        type: "nomeeting",
        start_at: format_time(start_at),
        end_at: format_time(end_at),
        raw_start: start_at
      }
    end

    merged.sort_by! { |x| x[:raw_start] }
    merged.each { |x| x.delete(:raw_start) }

    {
      years: years,
      year: year,
      available_dates: available_dates,
      selected_date: selected_date,
      schedules: merged
    }
  end

  # ===============================
  # MY SCHEDULE  (SQL-based)
  # ===============================
  def self.build_my_schedule(delegate:, params:)
    years = years_of(delegate.id)
    year  = params[:year].presence || "2025"

    conference = Conference.find_by(conference_year: year)
    return { error: :conference_not_found, years: years } unless conference

    available_dates = available_dates_of(conference)
    selected_date   = resolve_date(params[:date], delegate.id, conference, available_dates)
    return { error: :no_dates } unless selected_date

    conference_date = conference.conference_dates.find_by(on_date: selected_date)
    return { error: :date_not_found } unless conference_date

    schedules = fetch_my_schedule_via_sql(
      delegate:        delegate,
      conference_id:   conference.id,
      conference_date: conference_date,
      selected_date:   selected_date,
      time_param:      params[:time]
    )

    {
      years:           years,
      year:            year,
      available_dates: available_dates,
      selected_date:   selected_date,
      schedules:       schedules
    }
  end

  def self.fetch_my_schedule_via_sql(delegate:, conference_id:, conference_date:, selected_date:, time_param:)
    delegate_id        = delegate.id
    team_id            = delegate.team_id || 0
    conference_date_id = conference_date.id
    conn               = ActiveRecord::Base.connection

    # ── time slot filter ──────────────────────────────────
    slot      = resolve_time_slot(conference_date_id: conference_date_id,
                                  date: selected_date,
                                  time: time_param)
    time_cond = slot ? "AND s.start_at = #{conn.quote(slot.start_at.utc.to_s(:db))}" : ""
    date_q    = conn.quote(selected_date.to_s)

    # ══════════════════════════════════════════════════════
    # SQL A: ฉันเป็น TARGET
    #   team_delegates = booker delegate
    #   country        = s.country (เก็บตรงใน schedules table)
    # ══════════════════════════════════════════════════════
    sql_as_target = <<~SQL
      SELECT
        s.id,
        s.start_at,
        s.end_at,
        s.table_number,
        s.country       AS country,
        'target'        AS my_role,
        d.id            AS who_id,
        d.name          AS who_name,
        c.name          AS who_company
      FROM schedules s
      JOIN conference_dates cd
           ON  s.conference_date_id = cd.id
           AND cd.conference_id     = #{conference_id}
           AND cd.on_date           = #{date_q}
      LEFT JOIN delegates d  ON s.booker_id   = d.id
      LEFT JOIN companies c  ON d.company_id  = c.id
      WHERE s.target_id = #{team_id}
      AND s.booker_id IN (SELECT id FROM delegates)
      #{time_cond}
    SQL

    # ══════════════════════════════════════════════════════
    # SQL B: ฉันเป็น BOOKER
    #   team_delegates = target team's delegates
    #   country        = s.country (เก็บตรงใน schedules table)
    # ══════════════════════════════════════════════════════
    sql_as_booker = <<~SQL
      SELECT
        s.id,
        s.start_at,
        s.end_at,
        s.table_number,
        s.country       AS country,
        'booker'        AS my_role,
        d.id            AS who_id,
        d.name          AS who_name,
        c.name          AS who_company
      FROM schedules s
      JOIN conference_dates cd
           ON  s.conference_date_id = cd.id
           AND cd.conference_id     = #{conference_id}
           AND cd.on_date           = #{date_q}
      LEFT JOIN teams     t  ON s.target_id  = t.id
      LEFT JOIN delegates d  ON t.id         = d.team_id
      LEFT JOIN companies c  ON d.company_id = c.id
      WHERE s.booker_id = #{delegate_id}
      AND s.booker_id IN (SELECT id FROM delegates)
      #{time_cond}
    SQL

    rows = conn.execute(
      "#{sql_as_target} UNION ALL #{sql_as_booker} ORDER BY start_at ASC, id, who_id"
    ).to_a

    # ── group by schedule id → แปลงเป็น schedule hashes ─────
    schedule_hashes = rows.group_by { |r| r["id"] }.map do |_id, group|
      first     = group.first
      raw_start = Time.zone.parse(first["start_at"].to_s) rescue nil
      raw_end   = Time.zone.parse(first["end_at"].to_s)   rescue nil
      duration  = (raw_start && raw_end) ? ((raw_end - raw_start) / 60).to_i : 20
      has_table = first["table_number"].present?

      team_delegates = group.filter_map do |r|
        next if r["who_id"].blank?
        { id: r["who_id"].to_i, name: r["who_name"], company: r["who_company"] }
      end.uniq { |d| d[:id] }

      {
        type:             has_table ? "meeting" : "nomeeting",
        id:               first["id"].to_i,
        table_number:     first["table_number"],
        country:          first["country"].presence,
        conference_date:  selected_date.to_s,
        duration_minutes: duration,
        leave:            nil,
        team_delegates:   team_delegates,
        _raw_start:       raw_start,
        _raw_end:         raw_end,
        _schedule_id:     first["id"].to_i,
        _is_booker:       first["my_role"] == "booker"
      }
    end

    # ── group by start_at → เลือก 1 item ต่อ slot ────────────
    # priority: booker มีโต๊ะ > target มีโต๊ะ > booker ไม่มีโต๊ะ > target ไม่มีโต๊ะ
    meeting_items = schedule_hashes
      .group_by { |h| h[:_raw_start] }
      .map do |_, group|
        group.min_by do |h|
          if    h[:_is_booker] && h[:table_number].present? then 0
          elsif !h[:_is_booker] && h[:table_number].present? then 1
          elsif h[:_is_booker] then 2
          else 3
          end
        end
      end

    # ── เติม leave data ───────────────────────────────────
    schedule_ids = meeting_items.map { |m| m[:_schedule_id] }
    leave_map    = fetch_leave_map(schedule_ids)
    meeting_items.each { |m| m[:leave] = leave_map[m[:_schedule_id]] }

    # ── global events ─────────────────────────────────────
    event_scope = ConferenceSchedule.by_date(conference_date_id).only_events.sorted
    event_scope = event_scope.where(start_at: slot.start_at) if slot

    event_items = event_scope.map do |g|
      {
        type:       "event",
        id:         g.id,
        title:      g.title,
        _raw_start: g.start_at,
        _raw_end:   g.end_at
      }
    end

    # ── pure nomeeting slots (ไม่มี schedule row) ─────────
    all_slots = if slot
      [[slot.start_at, slot.end_at]]
    else
      Schedule
        .where(conference_date_id: conference_date_id)
        .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
        .distinct
        .pluck(:start_at, :end_at)
    end

    meeting_times = meeting_items.map { |m| m[:_raw_start] }.to_set
    event_times   = event_items.map   { |e| e[:_raw_start] }.to_set

    # pure slot → 3 fields เท่านั้น (ไม่มี id, leave ฯลฯ)
    nomeeting_items = all_slots.filter_map do |sa, ea|
      next if meeting_times.include?(sa)
      next if event_times.include?(sa)
      { type: "nomeeting", _raw_start: sa, _raw_end: ea }
    end

    # ── merge → sort → format ─────────────────────────────
    merged = (event_items + meeting_items + nomeeting_items)
               .sort_by { |x| x[:_raw_start] || Time.zone.now }

    merged.map do |item|
      raw_start = item.delete(:_raw_start)
      raw_end   = item.delete(:_raw_end)
      item.delete(:_schedule_id)
      item[:start_at] = raw_start&.in_time_zone("Asia/Bangkok")&.iso8601
      item[:end_at]   = raw_end&.in_time_zone("Asia/Bangkok")&.iso8601
      item.delete(:_is_booker)
      item
    end
  end

  # ──────────────────────────────────────────────────────────────
  # PRIVATE: ดึง leave data สำหรับ schedule_ids ที่กำหนด
  # ──────────────────────────────────────────────────────────────
  def self.fetch_leave_map(schedule_ids)
    return {} if schedule_ids.blank?

    LeaveForm.includes(:leave_type)
             .where(schedule_id: schedule_ids)
             .order(created_at: :desc)
             .each_with_object({}) do |lf, map|
      next if map.key?(lf.schedule_id)   # เก็บแค่อันล่าสุด

      map[lf.schedule_id] = {
        id:          lf.id,
        status:      lf.status,
        leave_type: {
          id:      lf.leave_type.id,
          code:    lf.leave_type.code,
          name_th: lf.leave_type.name_th,
          name_en: lf.leave_type.name_en
        },
        explanation: lf.explanation,
        reported_at: lf.reported_at&.in_time_zone("Asia/Bangkok")&.iso8601
      }
    end
  rescue => e
    Rails.logger.warn "[fetch_leave_map] #{e.message}"
    {}
  end

  # ===============================
  # SCHEDULE OTHERS
  # ===============================
  def self.build_schedule_others(viewer:, params:)
    target_delegate = Delegate.find_by(id: params[:delegate_id])
    return { error: :delegate_not_found } unless target_delegate

    years = years_of(target_delegate.id)
    unless years.map(&:to_s).include?("2025")
      return { error: :no_schedule_found, years: years }
    end

    result = build_timeline_for(delegate: target_delegate, params: params)
    result.merge(user: target_delegate)
  end

  # ===============================
  # INDEX
  # ===============================
  def self.build_index(delegate:, params:)
    page     = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 15).to_i, 100].min

    scope = with_full_data

    if params[:delegate_id].present?
      scope = scope.mine(params[:delegate_id])
    else
      scope = scope.mine(delegate.id)
    end

    if params[:year].present?
      scope = scope.joins(conference_date: :conference)
                  .where("conferences.conference_year = ?", params[:year])
    end

    if params[:date].present?
      begin
        date  = Date.parse(params[:date].to_s)
        scope = scope.joins(:conference_date)
                    .where(conference_dates: { on_date: date })
      rescue ArgumentError
        # invalid date — ignore
      end
    end

    total     = scope.count
    schedules = scope.sorted
                    .offset((page - 1) * per_page)
                    .limit(per_page)

    {
      page:      page,
      per_page:  per_page,
      total:     total,
      schedules: schedules
    }
  end

  # ===============================
    # TEAM DELEGATES
    # ===============================
    def team_delegates
      return [] unless team
      team.delegates
    end

    # ===============================
    # VALIDATIONS (private)
    # ===============================
    private

    def table_not_double_booked
      # Booth รองรับหลายคู่ได้ — ไม่ต้องเช็ค
      return if table_number.to_s.match?(/\ABooth\s/i)

      conflict = Schedule
        .where(table_number: table_number)
        .where(start_at: start_at)
        .where(conference_date_id: conference_date_id)
        .where.not(id: id)
        .exists?

      errors.add(:base, "โต๊ะ #{table_number} ถูกจองในช่วงเวลานี้แล้ว") if conflict
    end









end