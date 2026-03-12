# app/channels/announcement_channel.rb
#
# ⚠️  DEPRECATED — ไม่มี frontend subscribe channel นี้จริง
#
# admin_announce event ถูกส่งผ่าน NotificationChannel แทน:
#   NotificationChannel.broadcast_to(delegate, type: "admin_announce", ...)
#
# Channel นี้ไม่ได้ถูก broadcast จากที่ไหนในระบบ
# ถ้าไม่มีแผนใช้ในอนาคต → ควร remove ออก
#
class AnnouncementChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_delegate
  end
end