# spec/models/security_log_spec.rb
require "rails_helper"

RSpec.describe SecurityLog, type: :model do
  describe "associations" do
    it "belongs_to delegate with optional: true" do
      # ✅ ต้องไม่ crash เมื่อ delegate เป็น nil (login fail case)
      log = SecurityLog.new(event: "login", ip: "127.0.0.1")
      expect(log.valid?).to be true
    end

    it "can be created without delegate (login fail)" do
      expect do
        SecurityLog.create!(
          delegate: nil,
          event: "login",
          ip: "1.2.3.4"
        )
      end.not_to raise_error
    end

    it "can be created with delegate (normal login)" do
      delegate = create(:delegate)
      expect do
        SecurityLog.create!(
          delegate: delegate,
          event: "login",
          ip: "1.2.3.4"
        )
      end.not_to raise_error
    end
  end
end
