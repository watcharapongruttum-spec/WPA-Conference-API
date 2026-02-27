module Chat
  class RoomStateService
    def self.open_room(viewer_id, target_id)
      REDIS.setex(ChatKeys.chat_open(viewer_id, target_id), 60, "1")
    end

    def self.close_room(viewer_id, target_id)
      REDIS.del(ChatKeys.chat_open(viewer_id, target_id))
    end

    def self.read_if_unlocked(viewer_id, target_id)
      lock_key = ChatKeys.read_lock(viewer_id, target_id)
      return if REDIS.get(lock_key)

      REDIS.setex(lock_key, 2, "1")
      Chat::ReadService.mark_room(viewer_id, target_id)
    end

    def self.recipient_open?(recipient_id, sender_id)
      REDIS.get(ChatKeys.chat_open(recipient_id, sender_id)) == "1"
    end
  end
end
