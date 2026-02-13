module Chat
  class PresenceService
    PREFIX = "online_user"

    def self.online(user_id)
      REDIS.set("#{PREFIX}:#{user_id}", "1")
    end

    def self.offline(user_id)
      REDIS.del("#{PREFIX}:#{user_id}")
    end

    def self.online?(user_id)
      REDIS.get("#{PREFIX}:#{user_id}") == "1"
    end
  end
end
