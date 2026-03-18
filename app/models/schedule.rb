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
    team_id  = delegate&.team_id

    if team_id
      where("booker_id = :did OR target_id = :tid", did: delegate_id, tid: team_id)
    else
      where(booker_id: delegate_id)
    end
  }

  scope :not_mine, lambda { |delegate_id|
    delegate = Delegate.find_by(id: delegate_id)
    team_id  = delegate&.team_id

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

    year       = params[:year].presence || "2025"
    conference = Conference.find_by(conference_year: year)
    return { error: :conference_not_found, years: years } unless conference

    available_dates = available_dates_of(conference)
    selected_date   = resolve_date(params[:date], delegate.id, conference, available_dates)
    return { error: :no_dates } unless selected_date

    conference_date = conference.conference_dates.find_by(on_date: selected_date)
    return { error: :date_not_found } unless conference_date

    slot = resolve_time_slot(
      conference_date_id: conference_date.id,
      date:               selected_date,
      time:               params[:time]
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
        type:      "event",
        id:        g.id,
        title:     g.title,
        start_at:  format_time(g.start_at),
        end_at:    format_time(g.end_at),
        raw_start: g.start_at
      }
    end

    personal.each do |s|
      merged << {
        type:       "meeting",
        serializer: s,
        start_at:   format_time(s.start_at),
        end_at:     format_time(s.end_at),
        raw_start:  s.start_at
      }
    end

    all_slots =
      if slot
        [[slot.start_at, slot.end_at]]
      else
        Schedule
          .where(conference_date_id: conference_date.id)
          .where("delegate_id IS NOT NULL OR booker_id IS NOT NULL")
          .distinct
          .pluck(:start_at, :end_at)
      end

    personal_times = personal.map(&:start_at).to_set
    event_times    = global.map(&:start_at).to_set

    all_slots.each do |start_at, end_at|
      next if personal_times.include?(start_at)
      next if event_times.include?(start_at)

      merged << {
        type:      "nomeeting",
        start_at:  format_time(start_at),
        end_at:    format_time(end_at),
        raw_start: start_at
      }
    end

    merged.sort_by! { |x| x[:raw_start] }
    merged.each { |x| x.delete(:raw_start) }

    {
      years:           years,
      year:            year,
      available_dates: available_dates,
      selected_date:   selected_date,
      schedules:       merged
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

  # =====================================================
  # PRIVATE: fetch schedule via single CTE SQL
  #
  # SQL structure:
  #   meeting_detail  → meetings ของ delegate (ทั้ง target/booker side)
  #   events          → conference events (allow_booking = false)
  #   base → ordered → gaps → nomeeting slots ระหว่าง meeting+event
  #
  # หมายเหตุ: เพิ่ม s.id ใน meeting_detail เพื่อใช้กับ leave_map
  # =====================================================
  def self.fetch_my_schedule_via_sql(delegate:, conference_id:, conference_date:, selected_date:, time_param:)
    delegate_id        = delegate.id
    conference_date_id = conference_date.id
    conn               = ActiveRecord::Base.connection
    bkk_zone           = Time.find_zone("Asia/Bangkok")

    # ── time slot filter ──────────────────────────────────
    slot = resolve_time_slot(
      conference_date_id: conference_date_id,
      date:               selected_date,
      time:               time_param
    )

    slot_meeting_cond = slot ? "AND s.start_at = #{conn.quote(slot.start_at.utc.to_s(:db))}" : ""
    slot_event_cond   = slot ? "AND cs.start_at = #{conn.quote(slot.start_at.utc.to_s(:db))}" : ""
    # กรณีกรอง slot เดียว → ไม่มี gap ที่มีความหมาย → ปิด gaps ด้วย WHERE 1=0
    gaps_where        = slot ? "WHERE 1=0" : "WHERE next_start IS NOT NULL AND next_start > end_at"

    conf_id_q = conference_id.to_i
    del_id_q  = delegate_id.to_i
    date_q    = conn.quote(selected_date.to_s)

    # ══════════════════════════════════════════════════════
    # CTE SQL — meeting + event + nomeeting gaps ในครั้งเดียว
    # ══════════════════════════════════════════════════════
    sql = <<~SQL
      WITH
      -- 🟢 meeting detail
      meeting_detail AS (
        SELECT
          s.id,
          (s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') AS start_at,
          (s.end_at   AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') AS end_at,
          s.table_number  AS "table",
          s.country,
          t_me.id           AS my_team_id,
          t_me.name         AS my_team_name,
          b_me.trading_name AS my_company,
          t_op.id           AS op_team_id,
          t_op.name         AS op_team_name,
          b_op.trading_name AS op_company,
          json_agg(DISTINCT jsonb_build_object(
            'id',   d_me.id,
            'name', d_me.name
          )) FILTER (WHERE d_me.id IS NOT NULL) AS my_delegates,
          json_agg(DISTINCT jsonb_build_object(
            'id',   d_op.id,
            'name', d_op.name
          )) FILTER (WHERE d_op.id IS NOT NULL) AS op_delegates

        FROM schedules s
        JOIN conference_dates cd
          ON  s.conference_date_id = cd.id
          AND cd.conference_id     = #{conf_id_q}

        -- หาทีมของ delegate นี้
        LEFT JOIN delegates d_self ON d_self.id = #{del_id_q}
        LEFT JOIN teams     t_me   ON t_me.id   = d_self.team_id
        LEFT JOIN branches  b_me   ON t_me.branch_id = b_me.id

        -- หาทีมฝั่งตรงข้าม (opponent)
        LEFT JOIN teams t_op
          ON t_op.id = CASE
            WHEN s.target_id = t_me.id THEN s.booker_id
            ELSE s.target_id
          END
        LEFT JOIN branches b_op ON t_op.branch_id = b_op.id

        -- delegates ทีมเราและทีม opponent
        LEFT JOIN delegates d_me ON d_me.team_id = t_me.id
        LEFT JOIN delegates d_op ON d_op.team_id = t_op.id

        WHERE
          DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') = #{date_q}
          AND t_me.id IN (s.target_id, s.booker_id)
          AND s.table_number IS NOT NULL
          AND TRIM(s.table_number) <> ''
          #{slot_meeting_cond}

        GROUP BY
          s.id, s.start_at, s.end_at, s.table_number, s.country,
          t_me.id, t_me.name, b_me.trading_name,
          t_op.id, t_op.name, b_op.trading_name
      ),

      -- 🟡 conference events (allow_booking = false)
      events AS (
        SELECT
          cs.id,
          (cs.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') AS start_at,
          (cs.end_at   AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') AS end_at,
          cs.title
        FROM conference_schedules cs
        JOIN conference_dates cd
          ON  cs.conference_date_id = cd.id
          AND cd.conference_id      = #{conf_id_q}
        WHERE
          cs.allow_booking = false
          AND DATE(cs.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') = #{date_q}
          #{slot_event_cond}
      ),

      -- 🧩 หา gap (nomeeting) ระหว่าง meeting + event
      base AS (
        SELECT start_at, end_at FROM meeting_detail
        UNION ALL
        SELECT start_at, end_at FROM events
      ),
      ordered AS (
        SELECT *,
               LEAD(start_at) OVER (ORDER BY start_at) AS next_start
        FROM base
      ),
      gaps AS (
        SELECT
          end_at     AS start_at,
          next_start AS end_at
        FROM ordered
        #{gaps_where}
      )

      -- 🔥 FINAL: UNION ทั้ง 3 ประเภท (column count ต้องตรงกันทุก SELECT)
      SELECT
        m.id,
        m.start_at,
        m.end_at,
        'meeting'  AS type,
        NULL::text AS title,
        m.table,
        m.country,
        m.my_team_id,
        m.my_team_name,
        m.my_company,
        m.op_team_id,
        m.op_team_name,
        m.op_company,
        m.my_delegates,
        m.op_delegates
      FROM meeting_detail m

      UNION ALL

      SELECT
        e.id,
        e.start_at,
        e.end_at,
        'event',
        e.title,
        NULL::text,
        NULL::text,
        NULL::bigint,
        NULL::text,
        NULL::text,
        NULL::bigint,
        NULL::text,
        NULL::text,
        NULL::json,
        NULL::json
      FROM events e

      UNION ALL

      SELECT
        NULL::bigint,
        g.start_at,
        g.end_at,
        'nomeeting',
        NULL::text,
        NULL::text,
        NULL::text,
        NULL::bigint,
        NULL::text,
        NULL::text,
        NULL::bigint,
        NULL::text,
        NULL::text,
        NULL::json,
        NULL::json
      FROM gaps g

      ORDER BY start_at
    SQL

    rows = conn.execute(sql).to_a

    # ── แปลง rows → schedule items ──────────────────────
    items = rows.map do |row|
      raw_start = bkk_zone.parse(row["start_at"].to_s) rescue nil
      raw_end   = bkk_zone.parse(row["end_at"].to_s)   rescue nil

      case row["type"]

      # ── meeting ─────────────────────────────────────────
      when "meeting"
        duration = (raw_start && raw_end) ? ((raw_end - raw_start) / 60).to_i : 20

        # op_delegates → team_delegates ใน response
        raw_op = begin
          JSON.parse(row["op_delegates"].to_s)
        rescue
          []
        end

        team_delegates = raw_op.map do |d|
          { id: d["id"].to_i, name: d["name"], company: row["op_company"] }
        end.uniq { |d| d[:id] }

        {
          type:             "meeting",
          id:               row["id"].to_i,
          table_number:     row["table"],
          country:          row["country"].presence,
          conference_date:  selected_date.to_s,
          duration_minutes: duration,
          leave:            nil,            # เติมทีหลังจาก leave_map
          team_delegates:   team_delegates,
          _raw_start:       raw_start,
          _raw_end:         raw_end,
          _schedule_id:     row["id"].to_i
        }

      # ── event ────────────────────────────────────────────
      when "event"
        {
          type:       "event",
          id:         row["id"].to_i,
          title:      row["title"],
          _raw_start: raw_start,
          _raw_end:   raw_end
        }

      # ── nomeeting (gap) ──────────────────────────────────
      when "nomeeting"
        {
          type:       "nomeeting",
          _raw_start: raw_start,
          _raw_end:   raw_end
        }
      end
    end.compact

    # ── เติม leave data สำหรับ meeting items ─────────────
    meeting_items = items.select { |i| i[:type] == "meeting" }
    schedule_ids  = meeting_items.map { |m| m[:_schedule_id] }
    leave_map     = fetch_leave_map(schedule_ids)
    meeting_items.each { |m| m[:leave] = leave_map[m[:_schedule_id]] }

    # ── format → clean internal keys ─────────────────────
    items.map do |item|
      raw_start = item.delete(:_raw_start)
      raw_end   = item.delete(:_raw_end)
      item.delete(:_schedule_id)
      item[:start_at] = raw_start&.in_time_zone("Asia/Bangkok")&.iso8601
      item[:end_at]   = raw_end&.in_time_zone("Asia/Bangkok")&.iso8601
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
      next if map.key?(lf.schedule_id) # เก็บแค่อันล่าสุด

      map[lf.schedule_id] = {
        id:         lf.id,
        status:     lf.status,
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