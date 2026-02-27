# app/models/conference_date.rb
class ConferenceDate < ApplicationRecord
  belongs_to :conference
  has_many :conference_schedules, dependent: :destroy
  has_many :schedules, dependent: :destroy
end
