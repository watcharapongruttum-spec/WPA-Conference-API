# app/models/message_read.rb
class MessageRead < ApplicationRecord
  belongs_to :chat_message
  belongs_to :delegate

  validates :read_at, presence: true
  validates :delegate_id, uniqueness: { scope: :chat_message_id }

  # ============================================================
  # CLASS METHODS
  # ============================================================

  # mark messages เป็น read สำหรับ delegate คนนี้
  # return ids ที่เพิ่ง mark (ไม่รวมที่อ่านไปแล้ว)
  def self.mark_for(delegate:, message_ids:)
    return [] if message_ids.empty?

    now = Time.current

    # ดึง ids ที่ยังไม่เคยอ่าน
    already_read = where(
      chat_message_id: message_ids,
      delegate_id: delegate.id
    ).pluck(:chat_message_id)

    new_ids = message_ids - already_read
    return [] if new_ids.empty?

    # bulk insert — upsert เพื่อกัน race condition
    rows = new_ids.map do |msg_id|
      {
        chat_message_id: msg_id,
        delegate_id: delegate.id,
        read_at: now,
        created_at: now,
        updated_at: now
      }
    end

    upsert_all(rows, unique_by: %i[chat_message_id delegate_id])

    new_ids
  end

  # readers ของ message นั้น (ยกเว้น sender)
  # app/models/message_read.rb
  def self.readers_of(message_id)
    includes(:delegate)
      .where(chat_message_id: message_id)
      .map do |mr|
        d = mr.delegate
        {
          id: d.id,
          name: d.name,
          avatar_url: d.avatar_url.presence ||
            "https://ui-avatars.com/api/?name=#{CGI.escape(d.name.presence || 'Unknown')}&background=0D8ABC&color=fff",
          read_at: mr.read_at
        }
      end
  end
end
