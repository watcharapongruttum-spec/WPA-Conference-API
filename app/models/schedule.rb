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
  # TIMELINE (raw SQL)
  # ===============================

  def self.timeline_rows(conference_id:, filter_date:, delegate_id:, label: "timeline")
    sql = <<~SQL
      WITH params AS (
        SELECT
          $1::int  AS conference_id,
          $2::date AS filter_date,
          $3::int  AS delegate_id
      ),
      leave_data AS (
        SELECT
          lf.schedule_id,
          jsonb_build_object(
            'id',          lf.id,
            'status',      lf.status,
            'leave_type',  jsonb_build_object(
                             'id',      lt.id,
                             'code',    lt.code,
                             'name_th', lt.name_th,
                             'name_en', lt.name_en
                           ),
            'explanation', lf.explanation,
            'reported_at', to_char(
                             lf.reported_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
                             'YYYY-MM-DD"T"HH24:MI:SS+07:00'
                           )
          ) AS leave_json
        FROM leave_forms lf
        JOIN leave_types lt ON lt.id = lf.leave_type_id
      ),
      meeting_detail AS (
        SELECT
          s.id AS schedule_id,
          to_char(
            s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS start_at,
          to_char(
            s.end_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS end_at,
          s.table_number,
          EXTRACT(EPOCH FROM (s.end_at - s.start_at))::int / 60 AS duration_minutes,
          DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok')::text AS conference_date,
          c_op.country AS country,
          ld.leave_json,
          json_agg(DISTINCT jsonb_build_object(
            'id',      d_op.id,
            'name',    d_op.name,
            'company', b_op_d.trading_name
          )) FILTER (WHERE d_op.id IS NOT NULL) AS team_delegates
        FROM schedules s
        JOIN conference_dates cd
          ON s.conference_date_id = cd.id
          AND cd.conference_id = (SELECT conference_id FROM params)
        LEFT JOIN delegates d_self
          ON d_self.id = (SELECT delegate_id FROM params)
        LEFT JOIN teams t_me ON t_me.id = d_self.team_id
        LEFT JOIN delegates d_booker ON d_booker.id = s.booker_id
        LEFT JOIN teams t_op
          ON t_op.id = CASE
                WHEN s.target_id = t_me.id THEN d_booker.team_id
                ELSE s.target_id
            END
        LEFT JOIN delegates d_op ON d_op.team_id = t_op.id
        LEFT JOIN companies c_op ON c_op.id = t_op.company_id
        LEFT JOIN branches b_op_d ON b_op_d.id = d_op.branch_id
        LEFT JOIN leave_data ld ON ld.schedule_id = s.id
        WHERE
          DATE(s.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok')
            = (SELECT filter_date FROM params)
          AND t_me.id IN (s.target_id, d_booker.team_id) 
        GROUP BY
          s.id, s.start_at, s.end_at, s.table_number,
          c_op.country, ld.leave_json
      ),
      events AS (
        SELECT
          cs.id AS event_id,
          to_char(
            cs.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS start_at,
          to_char(
            cs.end_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok',
            'YYYY-MM-DD"T"HH24:MI:SS+07:00'
          ) AS end_at,
          cs.title
        FROM conference_schedules cs
        JOIN conference_dates cd
          ON cs.conference_date_id = cd.id
          AND cd.conference_id = (SELECT conference_id FROM params)
        WHERE
          cs.allow_booking = false
          AND DATE(cs.start_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Bangkok')
            = (SELECT filter_date FROM params)
      ),
      base AS (
        SELECT start_at, end_at FROM meeting_detail
        UNION ALL
        SELECT start_at, end_at FROM events
      ),
      ordered AS (
        SELECT *, LEAD(start_at) OVER (ORDER BY start_at) AS next_start
        FROM base
      ),
      gaps AS (
        SELECT end_at AS start_at, next_start AS end_at
        FROM ordered
        WHERE next_start IS NOT NULL AND next_start > end_at
      )
      SELECT
        m.start_at, m.end_at,
        'meeting'          AS type,
        m.schedule_id      AS id,
        NULL::text         AS title,
        m.table_number,
        m.country,
        m.conference_date,
        m.duration_minutes,
        m.leave_json,
        m.team_delegates
      FROM meeting_detail m
      UNION ALL
      SELECT
        e.start_at, e.end_at,
        'event', e.event_id, e.title,
        NULL::text, NULL::text, NULL::text,
        NULL::int, NULL::jsonb, NULL::json
      FROM events e
      UNION ALL
      SELECT
        g.start_at, g.end_at,
        'nomeeting', NULL::bigint, NULL::text,
        NULL::text, NULL::text, NULL::text,
        NULL::int, NULL::jsonb, NULL::json
      FROM gaps g
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
    rows.map do |row|
      case row["type"]
      when "event"
        { type: "event", id: row["id"], title: row["title"],
          start_at: row["start_at"], end_at: row["end_at"] }
      when "nomeeting"
        { type: "nomeeting", start_at: row["start_at"], end_at: row["end_at"] }
      else
        {
          type:             "meeting",
          id:               row["id"],
          table_number:     row["table_number"],
          country:          row["country"],
          conference_date:  row["conference_date"],
          duration_minutes: row["duration_minutes"],
          leave:            parse_json_column(row["leave_json"], single: true),
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

end