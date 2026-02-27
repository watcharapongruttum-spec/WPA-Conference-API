# app/models/company.rb
class Company < ApplicationRecord
  has_many :delegates, dependent: :destroy
  has_many :teams, dependent: :destroy
  has_one_attached :logo
end
