# app/services/chat/presence_service.rb
module Chat
  class PresenceService
    CONN_PREFIX = "chat:connections".freeze
    TTL = 2.minutes

    # -------------------------
    # User connected
    # -------------------------
    def self.online(user_id)
      key   = conn_key(user_id)
      count = REDIS.incr(key)
      REDIS.expire(key, TTL)
      Rails.logger.debug "[Presence] user=#{user_id} online count=#{count}"
      count
    rescue Redis::BaseError => e
      Rails.logger.warn "[Presence] Redis error in online: #{e.message}"
      0
    end

    # -------------------------
    # User disconnected
    # -------------------------
    def self.offline(user_id)
      key   = conn_key(user_id)
      count = REDIS.decr(key).to_i

      if count <= 0
        REDIS.del(key)
        count = 0
      else
        REDIS.expire(key, TTL)
      end

      Rails.logger.debug "[Presence] user=#{user_id} offline count=#{count}"
      count
    rescue Redis::BaseError => e
      Rails.logger.warn "[Presence] Redis error in offline: #{e.message}"
      0
    end

    # -------------------------
    # Is user online?
    # -------------------------
    def self.online?(user_id)
      connection_count(user_id).positive?
    rescue Redis::BaseError => e
      Rails.logger.warn "[Presence] Redis error in online?: #{e.message}"
      false  # fallback: ถือว่า offline เพื่อให้ FCM ยังส่งได้
    end

    # -------------------------
    # Heartbeat
    # -------------------------
    def self.refresh(user_id)
      key = conn_key(user_id)
      REDIS.set(key, 1) unless connection_count(user_id).positive?
      REDIS.expire(key, TTL)
    rescue Redis::BaseError => e
      Rails.logger.warn "[Presence] Redis error in refresh: #{e.message}"
    end

    # -------------------------
    # Get connection count
    # -------------------------
    def self.connection_count(user_id)
      REDIS.get(conn_key(user_id)).to_i
    rescue Redis::BaseError
      0
    end

    # -------------------------
    def self.conn_key(user_id)
      "#{CONN_PREFIX}:#{user_id}"
    end
  end
end
