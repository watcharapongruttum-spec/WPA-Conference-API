# app/services/chat/presence_service.rb
module Chat
  class PresenceService
    PREFIX      = "chat:online"
    CONN_PREFIX = "chat:connections"
    TTL         = 3600

    # return: connection count หลัง increment
    def self.online(user_id)
      count = REDIS.incr("#{CONN_PREFIX}:#{user_id}")
      REDIS.expire("#{CONN_PREFIX}:#{user_id}", TTL)
      REDIS.setex("#{PREFIX}:#{user_id}", TTL, "1")
      count
    end

    # return: connection count หลัง decrement
    def self.offline(user_id)
      count = REDIS.decr("#{CONN_PREFIX}:#{user_id}").to_i

      if count <= 0
        REDIS.del("#{CONN_PREFIX}:#{user_id}")
        REDIS.del("#{PREFIX}:#{user_id}")
      end

      count
    end

    def self.online?(user_id)
      REDIS.get("#{PREFIX}:#{user_id}") == "1"
    end

    # เรียกตอน heartbeat — ต่อ TTL ออกไป
    def self.refresh(user_id)
      return unless online?(user_id)
      REDIS.expire("#{PREFIX}:#{user_id}", TTL)
      REDIS.expire("#{CONN_PREFIX}:#{user_id}", TTL)
    end

    def self.connection_count(user_id)
      REDIS.get("#{CONN_PREFIX}:#{user_id}").to_i
    end
  end
end