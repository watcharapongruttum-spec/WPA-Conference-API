class LeaveForm < ApplicationRecord
  belongs_to :schedule
  belongs_to :leave_type 
  belongs_to :reported_by, class_name: "Delegate"
end




