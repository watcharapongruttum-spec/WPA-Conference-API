# app/models/conference_schedule.rb
class ConferenceSchedule < ApplicationRecord
  belongs_to :conference_date
end