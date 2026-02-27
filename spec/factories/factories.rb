# spec/factories/factories.rb
# FactoryBot factories สำหรับ test ทั้งหมด

FactoryBot.define do

  factory :company do
    sequence(:name) { |n| "Company #{n}" }
    sequence(:email) { |n| "company#{n}@example.com" }
    country { "TH" }
    encrypted_password { BCrypt::Password.create("password") }
  end

  factory :delegate do
    association :company
    sequence(:name)  { |n| "Delegate #{n}" }
    sequence(:email) { |n| "delegate#{n}@example.com" }
    password { "Password1" }
    password_confirmation { "Password1" }
    has_logged_in { false }
  end

  factory :chat_room do
    sequence(:title) { |n| "Room #{n}" }
    room_kind { :group }
  end

  factory :chat_message do
    association :sender, factory: :delegate
    content { "Test message" }

    # สำหรับ direct message
    trait :direct do
      association :recipient, factory: :delegate
      chat_room { nil }
    end

    # สำหรับ group message
    trait :group do
      association :chat_room
      recipient { nil }
    end
  end

  factory :message_read do
    association :chat_message
    association :delegate
    read_at { Time.current }
  end

  factory :notification do
    association :delegate
    notification_type { "new_message" }
    association :notifiable, factory: :chat_message
  end

  factory :connection_request do
    association :requester, factory: :delegate
    association :target, factory: :delegate
    status { :pending }
  end

  factory :conference do
    sequence(:name) { |n| "Conference #{n}" }
    is_current { true }
    conference_year { Date.today.year.to_s }
    slot_in_minute { 30 }
  end

  factory :conference_date do
    association :conference
    on_date { Date.today }
  end

  factory :table do
    association :conference
    sequence(:table_number) { |n| n.to_s }
  end

  factory :security_log do
    # delegate optional
    event { "login" }
    ip { "127.0.0.1" }
  end

end