# == Schema Information
#
# Table name: batch_payouts
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class BatchPayout < ApplicationRecord
  belongs_to :business_account
end
