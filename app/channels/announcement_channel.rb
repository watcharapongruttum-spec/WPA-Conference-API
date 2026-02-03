class AnnouncementChannel < ApplicationCable::Channel
  def subscribed
    stream_from "announcement"
  end
end
