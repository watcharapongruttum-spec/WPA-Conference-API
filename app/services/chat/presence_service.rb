# app/services/chat/presence_service.rb
module Chat
  class PresenceService
    CONN_PREFIX = "chat:connections"
    TTL = 30.seconds

    # -------------------------
    # User connected
    # -------------------------
    def self.online(user_id)
      key = conn_key(user_id)

      count = REDIS.incr(key)
      REDIS.expire(key, TTL)

      Rails.logger.debug "[Presence] user=#{user_id} online count=#{count}"

      count
    end

    # -------------------------
    # User disconnected
    # -------------------------
    def self.offline(user_id)
      key = conn_key(user_id)

      count = REDIS.decr(key).to_i

      if count <= 0
        REDIS.del(key)
        count = 0
      else
        REDIS.expire(key, TTL)
      end

      Rails.logger.debug "[Presence] user=#{user_id} offline count=#{count}"

      count
    end

    # -------------------------
    # Is user online?
    # -------------------------
    def self.online?(user_id)
      connection_count(user_id) > 0
    end

    # -------------------------
    # Heartbeat
    # -------------------------
    def self.refresh(user_id)
      key = conn_key(user_id)

      if connection_count(user_id) > 0
        REDIS.expire(key, TTL)
        Rails.logger.debug "[Presence] user=#{user_id} refreshed"
      end
    end

    # -------------------------
    # Get connection count
    # -------------------------
    def self.connection_count(user_id)
      REDIS.get(conn_key(user_id)).to_i
    end

    # -------------------------
    private
    # -------------------------
    def self.conn_key(user_id)
      "#{CONN_PREFIX}:#{user_id}"
    end
  end
end