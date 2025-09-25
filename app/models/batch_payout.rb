# == Schema Information
#
# Table name: batch_payouts
#
#  id                                                                                                                                      :bigint           not null, primary key
#  closed_at(timestamp when the batch payout is closed i.e., its processed & available balance from temporary hold is released)            :datetime
#  completed_at(timestamp when the batch payout is processed i.e., it could have all suceedeed or a mixture of suceedeed, failed, pending) :datetime
#  failed_count(number of failed transactions in the batch payout)                                                                         :integer          default(0), not null
#  pending_count(number of pending transactions in the batch payout)                                                                       :integer          default(0), not null
#  requested_amount(Total amount requested for the batch payout)                                                                           :bigint           default(0), not null
#  requested_amount_currency(currency of the amount requested for the batch payout)                                                        :string(3)        not null
#  status(current status of the batch payout)                                                                                              :string           default("pending"), not null
#  successful_count(number of successful transactions in the batch payout)                                                                 :integer          default(0), not null
#  total_count(total number of transactions in the batch payout)                                                                           :integer          default(0), not null
#  created_at                                                                                                                              :datetime         not null
#  updated_at                                                                                                                              :datetime         not null
#  business_account_id                                                                                                                     :bigint           not null
#
# Indexes
#
#  index_batch_payouts_on_business_account_id  (business_account_id)
#
class BatchPayout < ApplicationRecord
  attribute :status, :string, default: "PENDING"
  enum :status, {
    pending: "PENDING",
    processing: "PROCESSING",
    completed: "COMPLETED",
    failed: "FAILED"
  }, prefix: true

  belongs_to :business_account
  has_many :transactions, dependent: :destroy
end
