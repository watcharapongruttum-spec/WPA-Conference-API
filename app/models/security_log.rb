class SecurityLog < ApplicationRecord
  # optional: true เพราะบางกรณี (เช่น login fail) delegate อาจเป็น nil
  belongs_to :delegate, optional: true
end