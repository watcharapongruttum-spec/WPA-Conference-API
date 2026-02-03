# app/models/schedule.rb
class Schedule < ApplicationRecord
  belongs_to :conference_date
  belongs_to :booker, class_name: 'Delegate'
  belongs_to :target, class_name: 'Delegate'
end