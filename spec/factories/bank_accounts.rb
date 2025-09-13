# == Schema Information
#
# Table name: bank_accounts
#
#  id                                                                         :bigint           not null, primary key
#  balance_cents(The balance of the bank account in cents)                    :bigint           default(0), not null
#  bic(The BIC of the bank account)                                           :string           not null
#  iban(The IBAN of the bank account)                                         :string           not null
#  created_at                                                                 :datetime         not null
#  updated_at                                                                 :datetime         not null
#  business_account_id(The business account that the bank account belongs to) :bigint           not null
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
    business_account { nil }
  end
end
