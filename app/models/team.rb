# app/models/team.rb
class Team < ApplicationRecord
  belongs_to :company
  has_many :delegates, dependent: :destroy
end
