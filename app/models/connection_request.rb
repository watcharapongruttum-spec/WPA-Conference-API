class ConnectionRequest < ApplicationRecord
  belongs_to :requester, class_name: 'Delegate'
  belongs_to :target, class_name: 'Delegate'
  
  enum status: { pending: 'pending', accepted: 'accepted', rejected: 'rejected' }
  
  validates :requester_id, uniqueness: {
    scope: :target_id,
    conditions: -> { where.not(status: 'rejected') }
  }
  validate :cannot_connect_to_self
  
  scope :accepted, -> { where(status: 'accepted') }
  scope :pending, -> { where(status: 'pending') }
  
  def accept
    update!(status: 'accepted', accepted_at: Time.current)
  end
  
  def reject
    update!(status: 'rejected')
  end
  
  private
  
  def cannot_connect_to_self
    errors.add(:target_id, 'Cannot connect to yourself') if requester_id == target_id
  end
end