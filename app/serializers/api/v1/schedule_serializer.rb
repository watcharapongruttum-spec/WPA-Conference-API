# app/serializers/api/v1/schedule_serializer.rb
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
  def start_at = TimeFormatter.format(object.start_at)
  def end_at   = TimeFormatter.format(object.end_at)

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
    lf = object.latest_leave_form
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
end