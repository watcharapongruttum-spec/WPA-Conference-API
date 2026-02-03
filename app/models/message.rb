class Message < ApplicationRecord
  belongs_to :sender, class_name: "Delegate"
  belongs_to :recipient, class_name: "Delegate"
end
