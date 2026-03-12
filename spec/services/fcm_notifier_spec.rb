# spec/services/fcm_notifier_spec.rb
require "rails_helper"

RSpec.describe FcmNotifier do
  let(:delegate)    { create(:delegate, device_token: "valid_token_longer_than_20_chars_x") }
  let(:no_token)    { create(:delegate, device_token: nil) }
  let(:short_token) { create(:delegate, device_token: "short") }

  before do
    allow(FcmService).to receive(:send_push).and_return(true)
  end

  # ─── new_message ──────────────────────────────────────────
  describe ".new_message" do
    let(:sender)  { create(:delegate) }
    let(:message) { create(:chat_message, sender: sender, recipient: delegate, content: "hello") }

    it "skips when device_token is nil" do
      msg = create(:chat_message, sender: sender, recipient: no_token)
      described_class.new_message(delegate: no_token, message: msg)
      expect(FcmService).not_to have_received(:send_push)
    end

    it "skips when device_token is too short" do
      msg = create(:chat_message, sender: sender, recipient: short_token)
      described_class.new_message(delegate: short_token, message: msg)
      expect(FcmService).not_to have_received(:send_push)
    end

    it "sends push with correct title and body" do
      described_class.new_message(delegate: delegate, message: message)
      expect(FcmService).to have_received(:send_push).with(
        token: delegate.device_token,
        title: "New Message",
        body:  "#{sender.name}: hello",
        data:  hash_including(type: "new_message")
      )
    end

    it "uses 📷 body for image message" do
      image_msg = create(:chat_message, sender: sender, recipient: delegate,
                                        content: "", message_type: "image")
      described_class.new_message(delegate: delegate, message: image_msg)
      expect(FcmService).to have_received(:send_push)
        .with(hash_including(body: "#{sender.name}: 📷 รูปภาพ"))
    end
  end

  # ─── new_group_message ────────────────────────────────────
  describe ".new_group_message" do
    let(:room)    { create(:chat_room, title: "Team Alpha", room_kind: :group) }
    let(:sender)  { create(:delegate) }
    let(:message) { create(:chat_message, sender: sender, chat_room: room, content: "yo") }

    it "uses room title as push title" do
      described_class.new_group_message(delegate: delegate, message: message)
      expect(FcmService).to have_received(:send_push)
        .with(hash_including(title: "Team Alpha"))
    end

    it "includes room_id in data" do
      described_class.new_group_message(delegate: delegate, message: message)
      expect(FcmService).to have_received(:send_push)
        .with(hash_including(data: hash_including(room_id: room.id.to_s)))
    end

    it "skips when no token" do
      described_class.new_group_message(delegate: no_token, message: message)
      expect(FcmService).not_to have_received(:send_push)
    end
  end

  # ─── leave_reported ───────────────────────────────────────
# แก้ส่วนนี้ใน spec/services/fcm_notifier_spec.rb
# บรรทัด ~73-86

  describe ".leave_reported" do
    let(:reporter)   { create(:delegate, :with_device_token) }
    let(:reportee)   { create(:delegate, :with_device_token) }
    # LeaveForm ใช้ reported_by_id ไม่ใช่ delegate
    let(:leave_form) { create(:leave_form, reported_by: reporter) }

    it "sends push with correct Thai title" do
      expect(FcmService).to receive(:send_push)
      FcmNotifier.leave_reported(leave_form: leave_form, delegate: reportee)
    end

    it "skips when no token" do
      reportee.update!(device_token: nil)
      expect(FcmService).not_to receive(:send_push)
      FcmNotifier.leave_reported(leave_form: leave_form, delegate: reportee)
    end
  end

  # ─── announce ─────────────────────────────────────────────
  describe ".announce" do
    it "sends push with announcement message" do
      described_class.announce(delegate: delegate, message: "Hello WPA", sent_at: "2026-01-01")
      expect(FcmService).to have_received(:send_push)
        .with(hash_including(title: "📢 WPA Announcement", body: "Hello WPA"))
    end

    it "truncates long message to 100 chars" do
      long_msg = "x" * 200
      described_class.announce(delegate: delegate, message: long_msg, sent_at: "2026-01-01")
      expect(FcmService).to have_received(:send_push)
        .with(hash_including(body: long_msg.truncate(100)))
    end

    it "skips when no token" do
      described_class.announce(delegate: no_token, message: "hi", sent_at: "2026-01-01")
      expect(FcmService).not_to have_received(:send_push)
    end
  end

  # ─── summary ──────────────────────────────────────────────
  describe ".summary" do
    it "sends summary push with count" do
      described_class.summary(
        delegate:          delegate,
        notification_type: "new_message",
        count:             5
      )
      expect(FcmService).to have_received(:send_push)
        .with(hash_including(body: "You have 5 unread notifications"))
    end

    it "uses room title for group message summary" do
      described_class.summary(
        delegate:          delegate,
        notification_type: "new_group_message",
        count:             3,
        context:           { room_title: "Dev Team" }
      )
      expect(FcmService).to have_received(:send_push)
        .with(hash_including(title: "Dev Team"))
    end

    it "skips when no token" do
      described_class.summary(delegate: no_token, notification_type: "new_message", count: 1)
      expect(FcmService).not_to have_received(:send_push)
    end
  end
end