# spec/factories/wpa_factories.rb
# ============================================================
# Factories สำหรับใช้กับ bug_fixes_spec.rb
# ============================================================

FactoryBot.define do

  factory :delegate do
    sequence(:name)  { |n| "Delegate #{n}" }
    sequence(:email) { |n| "delegate#{n}@wpa.test" }
    password { "password123" }
    confirmed_at { Time.current }

    trait :with_fcm_token do
      fcm_token { "fcm_token_#{SecureRandom.hex(8)}" }
    end
  end

  factory :connection_request do
    association :requester, factory: :delegate
    association :target,    factory: :delegate
    status { :pending }
  end

  factory :chat_room do
    sequence(:name) { |n| "Room #{n}" }
    room_type { :group }

    trait :group do
      room_type { :group }
    end

    trait :direct do
      room_type { :direct }
    end
  end

  factory :chat_room_member do
    association :chat_room
    association :delegate
  end

  factory :chat_message do
    association :chat_room
    association :sender, factory: :delegate
    content { "Test message" }
    message_type { "text" }
  end

  factory :leave_form do
    association :delegate
    date      { Date.today }
    reason    { "ป่วย" }
    explanation { nil }
  end

  factory :team do
    sequence(:name) { |n| "Team #{n}" }
  end

  factory :schedule do
    target_type { "team" }
    association :team
    target_id   { team.id }
    title       { "Test Schedule" }
    starts_at   { 1.hour.from_now }
    ends_at     { 2.hours.from_now }
  end

  factory :conference do
    sequence(:name) { |n| "Conference #{n}" }
    starts_at { 1.day.from_now }
    ends_at   { 3.days.from_now }
  end

end

# ============================================================
# spec/support/auth_helpers.rb
# ============================================================
module AuthHelpers
  def auth_headers(delegate)
    token = JwtService.encode(delegate_id: delegate.id)
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type"  => "application/json"
    }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end