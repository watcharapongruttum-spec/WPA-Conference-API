# spec/channels/chat_channel_spec.rb
require "rails_helper"

RSpec.describe ChatChannel, type: :channel do
  let(:company)   { create(:company) }
  let(:delegate)  { create(:delegate, company: company) }
  let(:recipient) { create(:delegate, company: company) }

  before { stub_connection current_delegate: delegate }

  describe "#subscribed" do
    it "subscribes and streams for current_delegate" do
      subscribe
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(delegate)
    end
  end

  describe "#typing_start" do
    before { subscribe }

    it "calls BroadcastService.typing_start" do
      allow(Chat::BroadcastService).to receive(:typing_start)
      perform :typing_start, { recipient_id: recipient.id }
      expect(Chat::BroadcastService).to have_received(:typing_start)
        .with(recipient, sender_id: delegate.id)
    end

    it "transmits error when recipient not found" do
      perform :typing_start, { recipient_id: 999_999 }
      expect(transmissions.last).to include("type" => "error")
    end
  end

  describe "#typing_stop" do
    before { subscribe }

    it "calls BroadcastService.typing_stop" do
      allow(Chat::BroadcastService).to receive(:typing_stop)
      perform :typing_stop, { recipient_id: recipient.id }
      expect(Chat::BroadcastService).to have_received(:typing_stop)
        .with(recipient, sender_id: delegate.id)
    end
  end

  describe "#send_message" do
    let(:message) { build(:chat_message, :direct, sender: delegate, recipient: recipient) }

    before do
      subscribe
      allow(Chat::SendMessageService).to receive(:call).and_return(message)
      allow(Chat::BroadcastService).to   receive(:new_message)
      allow(Notification::Pipeline).to   receive(:call)
    end

    it "calls SendMessageService" do
      perform :send_message, { recipient_id: recipient.id, content: "hi" }
      expect(Chat::SendMessageService).to have_received(:call)
        .with(sender: delegate, recipient_id: recipient.id, content: "hi")
    end

    it "broadcasts new_message" do
      perform :send_message, { recipient_id: recipient.id, content: "hi" }
      expect(Chat::BroadcastService).to have_received(:new_message).with(message)
    end

    it "triggers notification pipeline" do
      perform :send_message, { recipient_id: recipient.id, content: "hi" }
      expect(Notification::Pipeline).to have_received(:call).with(message)
    end

    it "transmits error on ValidationError" do
      allow(Chat::SendMessageService).to receive(:call)
        .and_raise(Chat::SendMessageService::ValidationError, "invalid")
      perform :send_message, { recipient_id: recipient.id, content: "" }
      expect(transmissions.last).to include("type" => "error", "message" => "invalid")
    end
  end
end