# app/models/table.rb
class Table < ApplicationRecord
  belongs_to :conference
  has_many :teams, dependent: :nullify
  has_many :schedules




  
end