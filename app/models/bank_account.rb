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
class InsufficientFundsError < StandardError; end

class BankAccount < ApplicationRecord
  belongs_to :business_account

  def available_balance_cents
    balance_cents - reserved_amount_cents
  end

  # Reserve funds for a batch payout
  def reserve_funds!(amount_cents)
    with_lock do
      reload
      if available_balance_cents < amount_cents
        raise InsufficientFundsError, "Insufficient funds: available #{available_balance_cents}, required #{amount_cents}"
      end
      update!(reserved_amount_cents: reserved_amount_cents + amount_cents)
    end
  end

  # Process a successful transaction
  def process_transaction_success!(amount_cents)
    with_lock do
      reload # Gets the latest value of the reserved_amount_cents especially useful in concurrent transactions
      update!(
        balance_cents: balance_cents - amount_cents,
        reserved_amount_cents: reserved_amount_cents - amount_cents
      )
    end
  end

  # Release reserved funds for failed transaction
  def release_reserved_funds!(amount_cents)
    with_lock do
      reload # Gets the latest value of the reserved_amount_cents especially usefulin concurrent transactions

      update!(reserved_amount_cents: reserved_amount_cents - amount_cents)
    end
  end
end
