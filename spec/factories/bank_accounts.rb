# == Schema Information
#
# Table name: bank_accounts
#
#  id                                                                                                   :bigint           not null, primary key
#  balance_cents(The balance of the bank account in cents)                                              :bigint           default(0), not null
#  bic(The BIC of the bank account)                                                                     :string           not null
#  iban(The IBAN of the bank account)                                                                   :string           not null
#  reserved_amount_cents(Amount reserved for transactions in proceess/pending e.g., for a batch payout) :bigint           default(0), not null
#  created_at                                                                                           :datetime         not null
#  updated_at                                                                                           :datetime         not null
#  business_account_id(The business account that the bank account belongs to)                           :bigint           not null
#
# Indexes
#
#  index_bank_accounts_on_business_account_id  (business_account_id)
#
# Foreign Keys
#
#  fk_rails_...  (business_account_id => business_accounts.id)
#
FactoryBot.define do
  factory :bank_account do
    association :business_account
    balance_cents { 100000 }
    sequence(:iban) { |n| "FR142004101005050001#{n.to_s.rjust(4, '0')}" }
    bic { "BNPAFRPP" }
  end
end
