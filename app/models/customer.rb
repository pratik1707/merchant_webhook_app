class Customer < ApplicationRecord
  has_many :orders
  validates :email, presence: true, uniqueness: true

  x=1
end