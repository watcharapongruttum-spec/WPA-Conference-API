# spec/jobs/notification_delivery_job_spec.rb
require "rails_helper"

RSpec.describe NotificationDeliveryJob do
  let(:delegate) { create(:delegate, fcm_token: "valid_token_longer_than_20_chars_x") }

  before do
    allow(FcmNotifier).to receive(:new_message)
    allow(FcmNotifier).to receive(:new_group_message)
    allow(FcmNotifier).to receive(:leave_reported)
    allow(FcmNotifier).to receive(:summary)
    allow(Chat::PresenceService).to receive(:online?).and_return(false)
  end

  def run(notification)
    described_class.new.perform(notification.id)
  end

  # ─── Guards ───────────────────────────────────────────────
  it "skips when notification not found" do
    expect { described_class.new.perform(999_999) }.not_to raise_error
    expect(FcmNotifier).not_to have_received(:new_message)
  end

  it "skips when type not in FCM_ALLOWED_TYPES" do
    notif = create(:notification, delegate: delegate, notification_type: "connection_request")
    run(notif)
    expect(FcmNotifier).not_to have_received(:new_message)
  end

  it "skips when delegate is online" do
    allow(Chat::PresenceService).to receive(:online?).and_return(true)
    msg  = create(:chat_message, sender: create(:delegate), recipient: delegate)
    notif = create(:notification, delegate: delegate, notification_type: "new_message", notifiable: msg)
    run(notif)
    expect(FcmNotifier).not_to have_received(:new_message)
  end

  it "skips when delegate has no device token" do
    delegate.update!(fcm_token: nil)
    msg   = create(:chat_message, sender: create(:delegate), recipient: delegate)
    notif = create(:notification, delegate: delegate, notification_type: "new_message", notifiable: msg)
    run(notif)
    expect(FcmNotifier).not_to have_received(:new_message)
  end

  # ─── Single send ──────────────────────────────────────────
  context "when under burst threshold" do
    it "calls FcmNotifier.new_message for new_message type" do
      msg   = create(:chat_message, sender: create(:delegate), recipient: delegate)
      notif = create(:notification, delegate: delegate, notification_type: "new_message", notifiable: msg)
      run(notif)
      expect(FcmNotifier).to have_received(:new_message).with(delegate: delegate, message: msg)
    end

    it "calls FcmNotifier.new_group_message for new_group_message type" do
      room  = create(:chat_room, room_kind: :group)
      msg   = create(:chat_message, sender: create(:delegate), chat_room: room)
      notif = create(:notification, delegate: delegate, notification_type: "new_group_message", notifiable: msg)
      run(notif)
      expect(FcmNotifier).to have_received(:new_group_message).with(delegate: delegate, message: msg)
    end

    it "calls FcmNotifier.leave_reported for leave_reported type" do
      schedule   = create(:schedule)
      leave_form = create(:leave_form, reported_by: create(:delegate), schedule: schedule)
      notif      = create(:notification, delegate: delegate, notification_type: "leave_reported", notifiable: leave_form)
      run(notif)
      expect(FcmNotifier).to have_received(:leave_reported).with(delegate: delegate, leave_form: leave_form)
    end
  end

  # ─── Burst → summary ──────────────────────────────────────
  context "when at or above burst threshold (>= 2 in window)" do
    it "calls FcmNotifier.summary instead of single" do
      msg = create(:chat_message, sender: create(:delegate), recipient: delegate)
      # สร้าง notification 2 อันใน window เดียวกัน
      create(:notification, delegate: delegate, notification_type: "new_message",
             notifiable: msg, created_at: 30.seconds.ago)
      notif = create(:notification, delegate: delegate, notification_type: "new_message", notifiable: msg)

      run(notif)

      expect(FcmNotifier).to have_received(:summary)
        .with(hash_including(notification_type: "new_message", count: 2))
      expect(FcmNotifier).not_to have_received(:new_message)
    end
  end
end