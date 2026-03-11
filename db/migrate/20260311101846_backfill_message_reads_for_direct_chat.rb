# db/migrate/20260311090000_backfill_message_reads_for_direct_chat.rb
class BackfillMessageReadsForDirectChat < ActiveRecord::Migration[7.0]
  def up
    # backfill recipient reads — ทุก direct message ที่ recipient อ่านแล้ว (read_at present)
    # แต่ยังไม่มีใน message_reads
    execute <<~SQL
      INSERT INTO message_reads (chat_message_id, delegate_id, read_at, created_at, updated_at)
      SELECT
        cm.id           AS chat_message_id,
        cm.recipient_id AS delegate_id,
        cm.read_at      AS read_at,
        cm.read_at      AS created_at,
        cm.read_at      AS updated_at
      FROM chat_messages cm
      WHERE cm.chat_room_id IS NULL
        AND cm.recipient_id IS NOT NULL
        AND cm.read_at IS NOT NULL
        AND cm.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM message_reads mr
          WHERE mr.chat_message_id = cm.id
            AND mr.delegate_id     = cm.recipient_id
        )
      ON CONFLICT (chat_message_id, delegate_id) DO NOTHING
    SQL

    # backfill sender reads — sender ส่งแล้วถือว่าอ่านแล้วเสมอ
    execute <<~SQL
      INSERT INTO message_reads (chat_message_id, delegate_id, read_at, created_at, updated_at)
      SELECT
        cm.id         AS chat_message_id,
        cm.sender_id  AS delegate_id,
        cm.created_at AS read_at,
        cm.created_at AS created_at,
        cm.created_at AS updated_at
      FROM chat_messages cm
      WHERE cm.chat_room_id IS NULL
        AND cm.sender_id IS NOT NULL
        AND cm.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM message_reads mr
          WHERE mr.chat_message_id = cm.id
            AND mr.delegate_id     = cm.sender_id
        )
      ON CONFLICT (chat_message_id, delegate_id) DO NOTHING
    SQL

    say "Backfilled message_reads for direct chat messages"
  end

  def down
    # ลบเฉพาะ rows ที่มาจาก direct messages (ไม่กระทบ group chat)
    execute <<~SQL
      DELETE FROM message_reads
      WHERE chat_message_id IN (
        SELECT id FROM chat_messages WHERE chat_room_id IS NULL
      )
    SQL
  end
end