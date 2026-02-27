class Connection < ApplicationRecord
  belongs_to :requester, class_name: "Delegate"
  belongs_to :target, class_name: "Delegate"

  enum status: {
    pending: "pending",
    accepted: "accepted",
    rejected: "rejected"
  }
end
