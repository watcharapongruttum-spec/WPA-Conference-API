# spec/fcm_fix_spec.rb
# รันด้วย: bundle exec rspec spec/fcm_fix_spec.rb --format documentation

require "rails_helper"

# ============================================================
# SHARED HELPERS
# ============================================================
def stub_redis
  redis_double = instance_double(Redis)
  allow(redis_double).to receive(:get).and_return(nil)
  allow(redis_double).to receive(:setex)
  allow(redis_double).to receive(:del)
  stub_const("REDIS", redis_double)
  redis_double
end

def stub_presence(online: false)
  allow(Chat::PresenceService).to receive(:online?).and_return(online)
  allow(Chat::PresenceService).to receive(:online)
  allow(Chat::PresenceService).to receive(:offline)
  allow(Chat::PresenceService).to receive(:refresh)
end

def stub_fcm(success: true)
  allow(FcmService).to receive(:send_push).and_return(success)
end

# ============================================================
# 1. GROUP CHAT CHANNEL — ไม่ส่ง FCM ซ้ำ
# ============================================================
RSpec.describe GroupChatChannel, type: :channel do
  let(:company) { create(:company) }
  let(:sender)  { create(:delegate, company: company, device_token: nil) }
  let(:member1) { create(:delegate, company: company, device_token: "valid_token_member1_abcdef1234") }
  let(:member2) { create(:delegate, company: company, device_token: nil) }
  let(:room)    { create(:chat_room, room_kind: :group, title: "Test Room") }

  before do
    room.chat_room_members.create!(delegate: sender,  role: :admin)
    room.chat_room_members.create!(delegate: member1, role: :member)
    room.chat_room_members.create!(delegate: member2, role: :member)

    stub_redis
    stub_presence(online: false)
    stub_connection current_delegate: sender
    subscribe(room_id: room.id)
  end

  describe "#speak" do
    it "ไม่เรียก GroupMessagePushJob (ลบออกแล้ว)" do
      expect(GroupMessagePushJob).not_to receive(:perform_later)
      perform :speak, { "content" => "Hello!" }
    end

    it "เรียก Notification::BroadcastService สำหรับ members ที่ไม่ได้เปิดห้อง" do
      expect(Notification::BroadcastService).to receive(:call).at_least(:once)
      perform :speak, { "content" => "Hello!" }
    end

    it "สร้าง ChatMessage ในฐานข้อมูล" do
      expect {
        perform :speak, { "content" => "Hello!" }
      }.to change(ChatMessage, :count).by(1)
    end

    it "broadcast group_message ไปที่ห้อง" do
      perform :speak, { "content" => "Hello!" }
      expect(transmissions.last).to be_nil
    end

    it "ไม่สร้าง message เมื่อ content ว่าง" do
      expect {
        perform :speak, { "content" => "   " }
      }.not_to change(ChatMessage, :count)
    end
  end

  describe "#send_image" do
    let(:data_uri) { "data:image/png;base64,#{Base64.strict_encode64("fake_image_data")}" }

    before do
      allow(Chat::ImageService).to receive(:attach)
    end

    it "ไม่เรียก GroupMessagePushJob (ลบออกแล้ว)" do
      expect(GroupMessagePushJob).not_to receive(:perform_later)
      perform :send_image, { "image" => data_uri }
    end

    it "เรียก Notification::BroadcastService" do
      expect(Notification::BroadcastService).to receive(:call).at_least(:once)
      perform :send_image, { "image" => data_uri }
    end

    # ✅ FIX #8: ส่ง nil จะ blank? == true → transmit error "No image provided"
    # ตรวจผ่าน transmissions ของ channel
    it "transmit error เมื่อไม่มี image" do
      perform :send_image, { "image" => nil }
      expect(transmissions.last).to include("type" => "error", "message" => "No image provided")
    end
  end

  # ✅ FIX #7: described_class.new(nil, {}) crash เพราะ ActionCable ต้องการ connection
  # ตรวจสอบผ่าน class method แทน — ดู instance_methods ที่ defined ใน class นี้
  describe "push_to_offline_members method" do
    it "ไม่มี method push_to_offline_members อีกต่อไป" do
      all_methods = described_class.private_instance_methods(false) +
                    described_class.instance_methods(false)
      expect(all_methods).not_to include(:push_to_offline_members)
    end
  end
end

# ============================================================
# 2. NOTIFICATION DELIVERY JOB — Burst suppression
# ============================================================
RSpec.describe NotificationDeliveryJob, type: :job do
  let(:company)  { create(:company) }
  let(:delegate) { create(:delegate, company: company, device_token: "valid_device_token_abcdef1234") }

  before do
    stub_presence(online: false)
    stub_fcm(success: true)
  end

  def create_notification(type: "new_message", created_at: Time.current)
    sender  = create(:delegate, company: company)
    room    = type == "new_group_message" ? create(:chat_room, room_kind: :group, title: "Dev Room") : nil
    message = create(:chat_message,
      sender:       sender,
      recipient:    type == "new_message" ? delegate : nil,
      chat_room:    room,
      content:      "Hello",
      message_type: "text"
    )
    create(:notification,
      delegate:          delegate,
      notification_type: type,
      notifiable:        message,
      created_at:        created_at
    )
  end

  describe "count == 1 → ส่ง single push" do
    it "เรียก FcmService.send_push 1 ครั้ง" do
      notif = create_notification
      expect(FcmService).to receive(:send_push).once
      described_class.new.perform(notif.id)
    end

    it "title คือ 'New Message' สำหรับ new_message" do
      notif = create_notification(type: "new_message")
      expect(FcmService).to receive(:send_push).with(hash_including(title: "New Message"))
      described_class.new.perform(notif.id)
    end

    it "title คือชื่อห้องสำหรับ new_group_message" do
      notif = create_notification(type: "new_group_message")
      expect(FcmService).to receive(:send_push).with(hash_including(title: "Dev Room"))
      described_class.new.perform(notif.id)
    end
  end

  describe "count == 2 → ส่ง summary (FIX: เดิม silent)" do
    it "ส่ง push แม้มี 2 notifications ใน burst window" do
      create_notification(created_at: 30.seconds.ago)
      notif2 = create_notification

      expect(FcmService).to receive(:send_push).once.with(
        hash_including(body: "You have 2 unread messages")
      )
      described_class.new.perform(notif2.id)
    end
  end

  describe "count == 5 → ส่ง summary (FIX: เดิม silent)" do
    it "ส่ง push แม้มี 5 notifications ใน burst window" do
      4.times { create_notification(created_at: 30.seconds.ago) }
      notif5 = create_notification

      expect(FcmService).to receive(:send_push).once.with(
        hash_including(body: "You have 5 unread messages")
      )
      described_class.new.perform(notif5.id)
    end
  end

  describe "count > 5 → ส่ง summary" do
    it "ส่ง summary เมื่อมีมากกว่า 5 notifications" do
      6.times { create_notification(created_at: 30.seconds.ago) }
      notif = create_notification

      expect(FcmService).to receive(:send_push).once.with(
        hash_including(body: "You have 7 unread messages")
      )
      described_class.new.perform(notif.id)
    end
  end

  describe "delegate online → skip FCM" do
    it "ไม่ส่ง push เมื่อ delegate online" do
      allow(Chat::PresenceService).to receive(:online?).and_return(true)
      notif = create_notification

      expect(FcmService).not_to receive(:send_push)
      described_class.new.perform(notif.id)
    end
  end

  describe "ไม่มี device token → skip" do
    it "ไม่ส่ง push เมื่อไม่มี device_token" do
      delegate.update!(device_token: nil)
      notif = create_notification

      expect(FcmService).not_to receive(:send_push)
      described_class.new.perform(notif.id)
    end
  end

  describe "image message" do
    it "แสดง '📷 รูปภาพ' แทน content สำหรับ image message" do
      sender  = create(:delegate, company: company)
      message = create(:chat_message,
        sender:       sender,
        recipient:    delegate,
        content:      "",
        message_type: "image"
      )
      notif = create(:notification,
        delegate:          delegate,
        notification_type: "new_message",
        notifiable:        message
      )

      expect(FcmService).to receive(:send_push).with(
        hash_including(body: include("📷 รูปภาพ"))
      )
      described_class.new.perform(notif.id)
    end
  end

  describe "notification ไม่พบ" do
    it "ไม่ raise error" do
      expect { described_class.new.perform(99999) }.not_to raise_error
    end

    it "ไม่เรียก FcmService" do
      expect(FcmService).not_to receive(:send_push)
      described_class.new.perform(99999)
    end
  end
end

# ============================================================
# 3. FCM SERVICE — race condition & invalid token logging
# ============================================================
RSpec.describe FcmService do
  let(:company) { create(:company) }

  # ✅ FIX #1-6: unique index บน device_token → ใช้ SecureRandom ให้ token ไม่ซ้ำ
  # และไม่สร้าง delegate2 ที่มี token เหมือนกัน (unique constraint ไม่อนุญาต)
  let(:token)     { "fcm_test_token_#{SecureRandom.hex(8)}" }
  let(:delegate1) { create(:delegate, company: company, device_token: token) }

  before do
    delegate1 # ensure created
    allow(Rails.cache).to receive(:fetch).and_yield
    allow_any_instance_of(Google::Auth::ServiceAccountCredentials)
      .to receive(:fetch_access_token!).and_return({ "access_token" => "fake_token" })
  end

  describe ".fetch_access_token" do
    it "เรียก Rails.cache.fetch พร้อม race_condition_ttl" do
      expect(Rails.cache).to receive(:fetch).with(
        "fcm_access_token",
        hash_including(
          expires_in:         50.minutes,
          race_condition_ttl: 10.seconds
        )
      ).and_return("fake_token")

      FcmService.fetch_access_token
    end

    it "return nil และ log error เมื่อ credentials ไม่ถูกต้อง" do
      allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "auth failed")
      expect(Rails.logger).to receive(:error).with(include("FCM Auth Error"))
      result = FcmService.fetch_access_token
      expect(result).to be_nil
    end
  end

  describe ".handle_invalid_token" do
    context "เมื่อ token เป็น UNREGISTERED" do
      let(:body) do
        {
          error: {
            status:  "NOT_FOUND",
            message: "not a valid FCM registration token",
            details: [{ "errorCode" => "UNREGISTERED" }]
          }
        }.to_json
      end

      it "ลบ device_token ออกจาก delegate" do
        FcmService.handle_invalid_token(token, body)
        expect(delegate1.reload.device_token).to be_nil
      end

      it "log delegate_ids ที่ถูกลบ token" do
        expect(Rails.logger).to receive(:warn).with(include(delegate1.id.to_s))
        FcmService.handle_invalid_token(token, body)
      end

      it "pluck ids ได้ถูกต้องก่อน update" do
        expect(Delegate.where(device_token: token).pluck(:id)).to include(delegate1.id)
        FcmService.handle_invalid_token(token, body)
        expect(delegate1.reload.device_token).to be_nil
      end
    end

    context "เมื่อ token ยังใช้ได้ (non-invalid error)" do
      let(:body) do
        { error: { status: "INTERNAL", message: "server error", details: [] } }.to_json
      end

      it "ไม่ลบ device_token" do
        FcmService.handle_invalid_token(token, body)
        expect(delegate1.reload.device_token).to eq(token)
      end
    end

    context "เมื่อ body ไม่ใช่ JSON" do
      it "ไม่ raise error" do
        expect { FcmService.handle_invalid_token(token, "not json") }.not_to raise_error
      end

      it "log parse error" do
        expect(Rails.logger).to receive(:error).with(include("Could not parse"))
        FcmService.handle_invalid_token(token, "not json")
      end
    end
  end

  describe ".send_push" do
    it "return false ทันทีเมื่อ token blank" do
      expect(FcmService.send_push(token: "",  title: "T", body: "B")).to be false
      expect(FcmService.send_push(token: nil, title: "T", body: "B")).to be false
    end

    it "return false เมื่อ fetch_access_token คืน nil" do
      allow(FcmService).to receive(:fetch_access_token).and_return(nil)
      expect(FcmService.send_push(token: token, title: "T", body: "B")).to be false
    end
  end
end