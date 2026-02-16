class Schedule < ApplicationRecord
  # ===============================
  # RELATIONS
  # ===============================
  belongs_to :conference_date
  belongs_to :booker, class_name: "Delegate", optional: true
  belongs_to :target, class_name: "Delegate", optional: true

  belongs_to :table, optional: true
  belongs_to :delegate, optional: true
  belongs_to :team, foreign_key: :target_id, optional: true

  has_many :leave_forms

  # ===============================
  # DEFAULT INCLUDE
  # ===============================
  scope :with_full_data, -> {
    includes(
      :conference_date,
      leave_forms: :leave_type,
      booker: :company,
      target: :company
    )
  }

  # ===============================
  # BASIC SCOPES
  # ===============================
  scope :mine, ->(delegate_id) {
    where("schedules.booker_id = :id OR schedules.target_id = :id", id: delegate_id)
  }

  scope :not_mine, ->(delegate_id) {
    where.not("schedules.booker_id = :id OR schedules.target_id = :id", id: delegate_id)
  }

  scope :by_date, ->(conference_date_id) {
    where(conference_date_id: conference_date_id)
  }

  scope :sorted, ->(sort_by = nil, sort_dir = nil) {
    allowed = %w[start_at end_at created_at table_number]
    column  = allowed.include?(sort_by) ? sort_by : "start_at"
    dir     = sort_dir == "desc" ? "desc" : "asc"
    order("#{column} #{dir}")
  }

  # ===============================
  # SEARCH NAME
  # ===============================
  scope :search_name, ->(keyword) {
    joins(:booker, :target).where(
      "bookers_delegates.name ILIKE :k OR targets_delegates.name ILIKE :k",
      k: "%#{keyword}%"
    )
  }

  # ===============================
  # YEARS
  # ===============================
  def self.years_of(delegate_id)
    joins(conference_date: :conference)
      .mine(delegate_id)
      .pluck("conferences.conference_year")
      .uniq
      .sort
  end

  # ===============================
  # AVAILABLE DATES
  # ===============================
  def self.available_dates_of(conference)
    conference.conference_dates.order(:on_date).pluck(:on_date)
  end

  # ===============================
  # RESOLVE DATE
  # ===============================
  def self.resolve_date(params_date, delegate_id, conference, available_dates)
    return Date.parse(params_date) rescue nil if params_date.present?

    first = joins(:conference_date)
              .where(conference_dates: { conference_id: conference.id })
              .mine(delegate_id)
              .order("conference_dates.on_date ASC")
              .first

    first&.conference_date&.on_date || available_dates.first
  end

  # ===============================
  # FORMAT TIME
  # ===============================
  def self.format_time(time)
    return nil unless time
    time.utc.iso8601(3)
  end

  # =====================================================
  # CENTRAL TIMELINE BUILDER (ใหม่)
  # =====================================================
  def self.build_timeline_for(delegate:, params:)
    years = years_of(delegate.id)

    year = params[:year].presence || years.last || Date.today.year.to_s
    conference = Conference.find_by(conference_year: year)
    return { error: :conference_not_found, years: years } unless conference

    available_dates = available_dates_of(conference)
    selected_date   = resolve_date(params[:date], delegate.id, conference, available_dates)
    return { error: :no_dates } unless selected_date

    conference_date = conference.conference_dates.find_by(on_date: selected_date)
    return { error: :date_not_found } unless conference_date

    # PERSONAL MEETINGS
    personal = with_full_data
                .mine(delegate.id)
                .by_date(conference_date.id)
                .sorted
                .to_a

    # GLOBAL EVENTS
    global = ConferenceSchedule
              .by_date(conference_date.id)
              .only_events
              .sorted
              .to_a

    merged = []

    # EVENTS
    global.each do |g|
      merged << {
        type: "event",
        id: g.id,
        title: g.title,
        start_at: format_time(g.start_at),
        end_at: format_time(g.end_at),
        raw_start: g.start_at,
        table_number: nil,
        delegate: nil,
        leave: nil
      }
    end

    # MEETINGS
    personal.each do |s|
      merged << {
        type: "meeting",
        serializer: s,
        start_at: format_time(s.start_at),
        end_at: format_time(s.end_at),
        raw_start: s.start_at
      }
    end

    # SORT
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
  # MY SCHEDULE (แก้ให้เรียกกลาง)
  # ===============================
  def self.build_my_schedule(delegate:, params:)
    build_timeline_for(delegate: delegate, params: params)
  end

  # ===============================
  # SCHEDULE OTHERS (แก้ให้เรียกกลาง)
  # ===============================
  def self.build_schedule_others(viewer:, params:)
    target_delegate = Delegate.find_by(id: params[:delegate_id])
    return { error: :delegate_not_found } unless target_delegate

    result = build_timeline_for(delegate: target_delegate, params: params)
    result.merge(user: target_delegate)
  end

  # ===============================
  # INDEX
  # ===============================
  def self.build_index(delegate:, params:)
    page     = params[:page].to_i > 0 ? params[:page].to_i : 1
    per_page = params[:per_page].to_i > 0 ? params[:per_page].to_i : 20
    offset   = (page - 1) * per_page

    q = with_full_data
    q = q.not_mine(delegate.id) if delegate
    q = q.search_name(params[:search]) if params[:search].present?
    q = q.sorted(params[:sort_by], params[:sort_dir])

    total = q.count
    q = q.offset(offset).limit(per_page)

    {
      page: page,
      per_page: per_page,
      total: total,
      schedules: q.to_a
    }
  end

  # ===============================
  # MERGE TIMELINE (ของเดิม)
  # ===============================
  def self.merge_timeline(personal:, global:)
    items = []

    global.each do |g|
      items << {
        type: "event",
        id: g.id,
        title: g.title,
        start_at: g.start_at,
        end_at: g.end_at,
        is_meeting: false
      }
    end

    personal.each do |s|
      items << {
        type: "meeting",
        id: s.id,
        start_at: s.start_at,
        end_at: s.end_at,
        serializer: s
      }
    end

    items.sort_by { |i| i[:start_at] }
  end

  # ===============================
  # TEAM DELEGATES (ของเดิม)
  # ===============================
  def team_delegates
    return Delegate.none unless target_id
    Delegate.where(team_id: target_id)
  end
end
