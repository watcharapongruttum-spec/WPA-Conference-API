# spec/factories/wpa_factories.rb
# เฉพาะ factories ที่ไม่มีใน factories.rb
# หมายเหตุ: ย้าย RSpec.configure ออกมาจากไฟล์นี้แล้ว
#            เพราะ factories ถูกโหลดก่อน RSpec จะพร้อม

FactoryBot.define do

  factory :chat_room_member do
    association :chat_room
    association :delegate
  end

  factory :leave_form do
    association :delegate
    date        { Date.today }
    reason      { "ป่วย" }
    explanation { nil }
  end

  factory :team do
    association :company   # Team มี validates company must exist
    sequence(:name) { |n| "Team #{n}" }
  end

  factory :schedule do
    association :team
    title     { "Test Schedule" }
    starts_at { 1.hour.from_now }
    ends_at   { 2.hours.from_now }
  end

end