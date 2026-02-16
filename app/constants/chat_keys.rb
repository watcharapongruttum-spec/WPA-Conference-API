module ChatKeys
  PREFIX = "chat"

  def self.chat_open(viewer_id, target_id)
    "#{PREFIX}:open:#{viewer_id}:#{target_id}"
  end

  def self.read_lock(viewer_id, target_id)
    "#{PREFIX}:read_lock:#{viewer_id}:#{target_id}"
  end

  def self.user_online(user_id)
    "#{PREFIX}:online:#{user_id}"
  end
end
