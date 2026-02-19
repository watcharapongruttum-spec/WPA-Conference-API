# app/services/chat/presence_service.rb
module Chat
  class PresenceService

    # 🔴 FIX: เปลี่ยน PREFIX จาก "online_user" → "chat:online"
    # เดิม ChatChannel set key "chat:online:#{id}"
    # แต่ PresenceService.online? check key "online_user:#{id}"
    # → online? คืน false เสมอ แม้ user จะ online จริงๆ
    PREFIX = "chat:online"

    def self.online(user_id)
      REDIS.setex("#{PREFIX}:#{user_id}", 3600, "1")
    end

    def self.offline(user_id)
      REDIS.del("#{PREFIX}:#{user_id}")
    end

    def self.online?(user_id)
      REDIS.get("#{PREFIX}:#{user_id}") == "1"
    end
  end
end