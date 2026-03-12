# spec/services/notification/pipeline_spec.rb
require "rails_helper"

RSpec.describe Notification::Pipeline do
  let(:sender)    { create(:delegate) }
  let(:recipient) { create(:delegate) }
  let(:room)      { create(:chat_room, room_kind: :group) }

  before do
    allow(NotificationChannel).to receive(:broadcast_to)
    allow(NotificationDeliveryJob).to receive(:set).and_return(NotificationDeliveryJob)
    allow(NotificationDeliveryJob).to receive(:perform_later)
    allow(Chat::PresenceService).to receive(:online?).and_return(false)
    allow(REDIS).to receive(:set).and_return(true)
    allow(REDIS).to receive(:get).and_return(nil)
  end

  # ─── .call (direct message) ───────────────────────────────
  describe ".call" do
    let(:message) { create(:chat_message, sender: sender, recipient: recipient) }

    it "creates a Notification record" do
      expect { described_class.call(message) }
        .to change(Notification, :count).by(1)
    end

    it "sets notification_type to new_message" do
      described_class.call(message)
      expect(Notification.last.notification_type).to eq("new_message")
    end

    it "broadcasts via ActionCable" do
      described_class.call(message)
      expect(NotificationChannel).to have_received(:broadcast_to)
        .with(recipient, hash_including(type: "new_notification"))
    end

    it "enqueues NotificationDeliveryJob when delegate is offline" do
      described_class.call(message)
      expect(NotificationDeliveryJob).to have_received(:perform_later)
    end

    it "does not enqueue job when delegate is online" do
      allow(Chat::PresenceService).to receive(:online?).and_return(true)
      described_class.call(message)
      expect(NotificationDeliveryJob).not_to have_received(:perform_later)
    end

    it "skips when message has no recipient" do
      message.update_column(:recipient_id, nil)
      expect { described_class.call(message) }.not_to change(Notification, :count)
    end

    it "acquires Redis lock to prevent duplicates" do
      described_class.call(message)
      expect(REDIS).to have_received(:set)
        .with("notif_lock:#{message.id}", 1, nx: true, ex: 5)
    end
  end

  # ─── .call_group ──────────────────────────────────────────
  describe ".call_group" do
    let(:member1) { create(:delegate) }
    let(:member2) { create(:delegate) }
    let(:message) { create(:chat_message, sender: sender, chat_room: room) }

    before do
      create(:chat_room_member, chat_room: room, delegate: member1)
      create(:chat_room_member, chat_room: room, delegate: member2)
    end

    it "creates Notification for each member except sender" do
      expect {
        described_class.call_group(message, room: room, sender: sender)
      }.to change(Notification, :count).by(2)
    end

    it "skips members who have room open" do
      allow(REDIS).to receive(:get)
        .with("group_chat_open:#{room.id}:#{member1.id}")
        .and_return("1")

      expect {
        described_class.call_group(message, room: room, sender: sender)
      }.to change(Notification, :count).by(1)
    end

    it "broadcasts to each recipient" do
      described_class.call_group(message, room: room, sender: sender)

      expect(NotificationChannel).to have_received(:broadcast_to)
        .with(member1, anything)
      expect(NotificationChannel).to have_received(:broadcast_to)
        .with(member2, anything)
    end

    it "does not create notification for sender" do
      create(:chat_room_member, chat_room: room, delegate: sender)
      described_class.call_group(message, room: room, sender: sender)

      notifications = Notification.where(delegate: sender)
      expect(notifications).to be_empty
    end
  end

  # ─── .call_leave ──────────────────────────────────────────
  describe ".call_leave" do
    let(:booker)     { create(:delegate) }
    let(:schedule)   { create(:schedule, booker: booker) }
    let(:leave_form) { create(:leave_form, reported_by: sender, schedule: schedule) }

    it "creates notification for booker" do
      expect { described_class.call_leave(leave_form) }
        .to change(Notification, :count).by(1)
    end

    it "sets notification_type to leave_reported" do
      described_class.call_leave(leave_form)
      expect(Notification.last.notification_type).to eq("leave_reported")
    end

    it "skips when reporter is the booker" do
      leave_form.schedule.update!(booker: sender)
      expect { described_class.call_leave(leave_form) }
        .not_to change(Notification, :count)
    end

    it "skips when schedule has no booker" do
      leave_form.schedule.update!(booker: nil)
      expect { described_class.call_leave(leave_form) }
        .not_to change(Notification, :count)
    end
  end

  # ─── .call_connection ─────────────────────────────────────
  describe ".call_connection" do
    let(:connection) { create(:connection_request, requester: sender, target: recipient) }

    it "creates notification with correct type" do
      described_class.call_connection(
        delegate:   recipient,
        type:       "connection_request",
        notifiable: connection
      )
      expect(Notification.last.notification_type).to eq("connection_request")
    end

    it "broadcasts via ActionCable but does NOT enqueue FCM job" do
      described_class.call_connection(
        delegate:   recipient,
        type:       "connection_request",
        notifiable: connection
      )
      expect(NotificationChannel).to have_received(:broadcast_to).with(recipient, anything)
      expect(NotificationDeliveryJob).not_to have_received(:perform_later)
    end
  end

  # ─── .call_announce ───────────────────────────────────────
  describe ".call_announce" do
    before { allow(AnnouncementPushJob).to receive(:perform_later) }

    it "broadcasts via ActionCable" do
      described_class.call_announce(delegate: recipient, message: "Hello", sent_at: "2026-01-01")
      expect(NotificationChannel).to have_received(:broadcast_to)
        .with(recipient, hash_including(type: "new_notification"))
    end

    it "enqueues AnnouncementPushJob when delegate has token" do
      recipient.update!(fcm_token: "valid_token_longer_than_20_chars_x")
      described_class.call_announce(delegate: recipient, message: "Hello", sent_at: "2026-01-01")
      expect(AnnouncementPushJob).to have_received(:perform_later)
    end

    it "does not enqueue job when no device token" do
      recipient.update!(fcm_token: nil)
      described_class.call_announce(delegate: recipient, message: "Hello", sent_at: "2026-01-01")
      expect(AnnouncementPushJob).not_to have_received(:perform_later)
    end
  end
end