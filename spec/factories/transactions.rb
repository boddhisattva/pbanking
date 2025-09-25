# == Schema Information
#
# Table name: transactions
#
#  id                                                                :bigint           not null, primary key
#  amount_cents(The amount of the transaction in cents)              :bigint           not null
#  amount_currency(The currency of the transaction)                  :string           not null
#  last_error(The last error message of a transaction)               :string
#  note(The sender-specified note)                                   :text
#  receiver(The receiver of the transaction)                         :string           not null
#  recipient_type(The type of the recipient - email)                 :string           not null
#  status(The current status of a transaction)                       :string           default("pending")
#  created_at                                                        :datetime         not null
#  updated_at                                                        :datetime         not null
#  bank_account_id(The bank account that the transaction belongs to) :bigint           not null
#  batch_payout_id                                                   :bigint
#
# Indexes
#
#  index_transactions_on_bank_account_id  (bank_account_id)
#  index_transactions_on_batch_payout_id  (batch_payout_id)
#
# Foreign Keys
#
#  fk_rails_...  (bank_account_id => bank_accounts.id)
#
FactoryBot.define do
  factory :transaction do
    association :bank_account
    recipient_type { "email" }
    sequence(:receiver) { |n| "user#{n}@example.com" }
    amount_cents { 5000 }
    amount_currency { "EUR" }
    note { "Payment for services" }
  end
end
