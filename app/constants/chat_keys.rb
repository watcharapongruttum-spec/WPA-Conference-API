# app/constants/chat_keys.rb
module ChatKeys
  PREFIX = "chat".freeze

  def self.chat_open(viewer_id, target_id)
    "#{PREFIX}:open:#{viewer_id}:#{target_id}"
  end

  def self.read_lock(viewer_id, target_id)
    "#{PREFIX}:read_lock:#{viewer_id}:#{target_id}"
  end

  def self.presence(user_id)
    "#{PREFIX}:presence:#{user_id}"
  end

  def self.typing(viewer_id, target_id)
    "#{PREFIX}:typing:#{viewer_id}:#{target_id}"
  end
end
