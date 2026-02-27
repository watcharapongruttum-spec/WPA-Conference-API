# app/models/conference_schedule.rb
class ConferenceSchedule < ApplicationRecord
  belongs_to :conference_date

  scope :by_date, lambda { |conference_date_id|
    where(conference_date_id: conference_date_id)
  }

  # เอาเฉพาะ event กลาง ไม่เอา one-on-one slot
  scope :only_events, lambda {
    where(allow_booking: false)
  }

  scope :sorted, lambda {
    order(:start_at)
  }
end
