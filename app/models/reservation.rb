# app/models/reservation.rb
class Reservation < ApplicationRecord
  belongs_to :company
  belongs_to :conference
  belongs_to :member, class_name: "Company", optional: true
  has_many :delegates, dependent: :destroy
end
