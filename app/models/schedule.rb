class Schedule < ApplicationRecord
  # ===============================
  # RELATIONS
  # ===============================
  belongs_to :conference_date
  # FIX: booker_id คือ team_id ไม่ใช่ delegate id
  belongs_to :booker, class_name: "Team", foreign_key: :booker_id, optional: true
  belongs_to :table, optional: true
  belongs_to :delegate, optional: true
  belongs_to :team, foreign_key: :target_id, optional: true

  has_many :leave_forms

  has_one :latest_leave_form,
          -> { order(created_at: :desc) },
          class_name: "LeaveForm"

  validate :table_not_double_booked, if: -> { table_number.present? && start_at.present? }
  validate :no_double_booking

  # ===============================
  # DEFAULT INCLUDE
  # ===============================
  scope :with_full_data, lambda {
    includes(
      :conference_date,
      latest_leave_form: :leave_type,
      team: :delegates,
      booker: :delegates
    )
  }

  # ===============================
  # BASIC SCOPES
  # ===============================
  scope :mine, lambda { |delegate_id|
    delegate = Delegate.find_by(id: delegate_id)
    team_id  = delegate&.team_id

    if team_id
      where("booker_id = :tid OR target_id = :tid", tid: team_id)
    else
      where(booker_id: nil)
    end
  }

  scope :not_mine, lambda { |delegate_id|
    delegate = Delegate.find_by(id: delegate_id)
    team_id  = delegate&.team_id

    if team_id
      where.not(
        "schedules.booker_id = :tid OR schedules.target_id = :tid",
        tid: team_id
      )
    else
      where.not(booker_id: nil)
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
    left_joins(booker: :delegates).where(
      "delegates.name ILIKE :k",
      k: "%#{keyword}%"
    )
  }

  # ===============================
  # TIMELINE (raw SQL)
  # ===============================

  def self.timeline_rows(conference_id:, filter_date:, delegate_id:, label: "timeline")
    sql = <<~SQL
      WITH meeting_data AS (
        SELECT
          s.id,
          'meeting' AS type,
          to_char(
            s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS start_at,
          to_char(
            s.end_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS end_at,
          s.table_number,
          c_t.country,
          DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok')::text AS conference_date,
          EXTRACT(EPOCH FROM (s.end_at - s.start_at))::int / 60 AS duration_minutes,
          json_agg(
            jsonb_build_object(
              'id', d_op.id,
              'name', d_op.name,
              'company', c_op.name
            )
          ) FILTER (WHERE d_op.id IS NOT NULL) AS team_delegates
        FROM schedules s
        JOIN conference_dates cd ON cd.id = s.conference_date_id
        JOIN conferences c ON c.id = cd.conference_id
        -- FIX: ดึงทีมฝั่งตรงข้ามเสมอ (ถ้าเป็น booker → ดึง target, ถ้าเป็น target → ดึง booker)
        LEFT JOIN teams t ON t.id = CASE
          WHEN s.booker_id = (SELECT team_id FROM delegates WHERE id = $3 LIMIT 1)
          THEN s.target_id
          ELSE s.booker_id
        END
        LEFT JOIN delegates d_op ON d_op.team_id = t.id
        LEFT JOIN companies c_op ON c_op.id = d_op.company_id
        LEFT JOIN companies c_t ON c_t.id = t.company_id
        WHERE
          c.id = $1
          AND (
            s.booker_id = (SELECT team_id FROM delegates WHERE id = $3 LIMIT 1)
            OR s.target_id = (SELECT team_id FROM delegates WHERE id = $3 LIMIT 1)
          )
          AND s.table_number IS NOT NULL
          AND TRIM(s.table_number) <> ''
          AND DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') = $2::date
        GROUP BY
          s.id, s.start_at, s.end_at, s.table_number,
          c_t.country
      ),
      event_data AS (
        SELECT
          cs.id,
          'event' AS type,
          to_char(
            cs.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS start_at,
          to_char(
            cs.end_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS end_at,
          cs.title,
          cs.allow_booking
        FROM conference_schedules cs
        JOIN conference_dates cd ON cd.id = cs.conference_date_id
        JOIN conferences c ON c.id = cd.conference_id
        WHERE
          c.id = $1
          AND DATE(cs.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok') = $2::date
      ),
      -- slot ที่ allow_booking=true แต่ไม่มี meeting ของ delegate นี้ → nomeeting
      nomeeting_slots AS (
        SELECT
          'nomeeting' AS type,
          e.start_at,
          e.end_at
        FROM event_data e
        WHERE e.allow_booking = true
          AND NOT EXISTS (
            SELECT 1 FROM meeting_data m
            WHERE m.start_at = e.start_at
          )
      ),
      -- event ที่ allow_booking=false เท่านั้นที่แสดง
      real_events AS (
        SELECT * FROM event_data
        WHERE allow_booking = false
      )
      SELECT
        type,
        id,
        start_at,
        end_at,
        table_number,
        country,
        conference_date,
        duration_minutes,
        team_delegates,
        NULL::text AS title
      FROM meeting_data
      UNION ALL
      SELECT
        type,
        id,
        start_at,
        end_at,
        NULL, NULL, NULL, NULL, NULL,
        title
      FROM real_events
      UNION ALL
      SELECT
        type,
        NULL,
        start_at,
        end_at,
        NULL, NULL, NULL, NULL, NULL,
        NULL
      FROM nomeeting_slots
      ORDER BY start_at
    SQL

    connection.exec_query(sql, "#{label}_timeline", [conference_id, filter_date, delegate_id])
  end

  def self.available_years(conference_id:)
    sql = <<~SQL
      SELECT DISTINCT EXTRACT(YEAR FROM on_date)::int AS year
      FROM conference_dates
      WHERE conference_id = $1
      ORDER BY year
    SQL

    connection.exec_query(sql, "available_years", [conference_id]).map { |r| r["year"].to_s }
  end

  def self.available_dates(conference_id:, year:)
    sql = <<~SQL
      SELECT on_date
      FROM conference_dates
      WHERE conference_id = $1
        AND EXTRACT(YEAR FROM on_date) = $2
      ORDER BY on_date
    SQL

    connection.exec_query(sql, "available_dates", [conference_id, year]).map { |r| r["on_date"].to_s }
  end




  def self.format_timeline(rows)
    # ดึง leave_forms ทั้งหมดของ schedule ที่เกี่ยวข้อง
    schedule_ids = rows.map { |r| r["id"] }.compact
    leave_forms = LeaveForm
      .includes(:leave_type)
      .where(schedule_id: schedule_ids)
      .order(created_at: :desc)
      .each_with_object({}) do |lf, h|
        h[lf.schedule_id] ||= lf  # เก็บแค่อันล่าสุด
      end

    rows.map do |row|
      case row["type"]
      when "event"
        { type: "event", id: row["id"], title: row["title"],
          start_at: row["start_at"], end_at: row["end_at"] }
      when "nomeeting"
        { type: "nomeeting", start_at: row["start_at"], end_at: row["end_at"] }
      else
        lf = leave_forms[row["id"]]
        {
          type:             "meeting",
          id:               row["id"],
          table_number:     row["table_number"],
          country:          row["country"],
          conference_date:  row["conference_date"],
          duration_minutes: row["duration_minutes"],
          leave: lf ? {
            id:          lf.id,
            status:      lf.status,
            leave_type: {
              id:      lf.leave_type_id,
              name:    lf.leave_type&.name
            },
            explanation: lf.explanation,
            reported_at: lf.reported_at
          } : nil,
          team_delegates:   parse_json_column(row["team_delegates"]),
          start_at:         row["start_at"],
          end_at:           row["end_at"]
        }
      end
    end
  end







  # ===============================
  # PRIVATE CLASS METHODS
  # ===============================
  class << self
    private

    def parse_json_column(value, single: false)
      return (single ? nil : []) if value.nil?
      parsed = value.is_a?(String) ? JSON.parse(value) : value
      single ? parsed : Array(parsed)
    rescue JSON::ParserError
      single ? nil : []
    end
  end

  # ===============================
  # PRIVATE INSTANCE METHODS
  # ===============================
  private

  def no_double_booking
    return unless booker_id && start_at

    # เช็ค booker team ซ้ำในเวลาเดียวกัน
    if Schedule.where(booker_id: booker_id, start_at: start_at)
               .where.not(id: id)
               .exists?
      errors.add(:base, "Delegate is double booked at the same time")
    end

    # FIX: เช็คว่า booker team ถูก book เป็น target ในเวลาเดียวกันไหม
    if Schedule.where(target_id: booker_id, start_at: start_at)
               .where.not(id: id)
               .exists?
      errors.add(:base, "Your team is already scheduled as a guest at this time")
    end
  end

end