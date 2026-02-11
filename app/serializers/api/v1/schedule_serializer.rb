class Api::V1::ScheduleSerializer < ActiveModel::Serializer
  attributes :id,
             :start_at,
             :end_at,
             :table_number,
             :country,
             :conference_date,
             :delegate,
             :duration_minutes,
             :leave

  # ===============================
  # TIME FORMAT
  # ===============================
  def start_at
    format_time(object.start_at)
  end

  def end_at
    format_time(object.end_at)
  end

  # ===============================
  # DATE
  # ===============================
  def conference_date
    object.conference_date&.on_date
  end

  # ===============================
  # DELEGATE
  # ===============================
  def delegate
    current_delegate = scope
    return nil unless current_delegate

    d =
      if object.booker_id == current_delegate.id
        object.target
      else
        object.booker
      end

    {
      id: d&.id,
      name: d&.name || "Unknown",
      company: d&.company&.name || "N/A"
    }
  end

  # ===============================
  # DURATION
  # ===============================
  def duration_minutes
    return 0 unless object.start_at && object.end_at
    ((object.end_at - object.start_at) / 60).to_i
  end

  # ===============================
  # LEAVE
  # ===============================
  def leave
    lf = object.leave_forms
               .order(created_at: :desc)
               .first

    return nil unless lf

    {
      id: lf.id,
      status: lf.status,
      leave_type: {
        id: lf.leave_type_id,
        code: lf.leave_type&.code,
        name_th: lf.leave_type&.name_th,
        name_en: lf.leave_type&.name_en
      },
      explanation: lf.explanation,
      reported_at: lf.reported_at
    }
  end

  # ===============================
  # PRIVATE
  # ===============================
  private
  def format_time(time)
    return nil unless time
    time.utc.iso8601(3)
  end

end
