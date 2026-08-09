class User < ApplicationRecord
  validates :email, presence: true
  validates :username, presence: true, length: { in: 3..20 }
  validates :age, numericality: true, allow_nil: true
end
