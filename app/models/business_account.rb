# == Schema Information
#
# Table name: business_accounts
#
#  id                                                 :bigint           not null, primary key
#  email(The email of the business account)           :string           not null
#  first_name(The first name of the business account) :string           not null
#  last_name(The last name of the business account)   :string           not null
#  created_at                                         :datetime         not null
#  updated_at                                         :datetime         not null
#
# Indexes
#
#  index_business_accounts_on_email  (email) UNIQUE
#
class BusinessAccount < ApplicationRecord
  validates :email, presence: true, uniqueness: true
  validates :first_name, presence: true
  validates :last_name, presence: true
end
