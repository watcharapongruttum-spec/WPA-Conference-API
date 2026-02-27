# app/models/conference.rb
class Conference < ApplicationRecord
  has_many :conference_dates, dependent: :destroy
  has_many :conference_schedules, through: :conference_dates
  has_many :tables, dependent: :destroy
  has_many :reservations, dependent: :destroy
end
