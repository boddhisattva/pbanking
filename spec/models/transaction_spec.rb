# == Schema Information
#
# Table name: transactions
#
#  id                                                                :bigint           not null, primary key
#  amount_cents(The amount of the transaction in cents)              :bigint           not null
#  amount_currency(The currency of the transaction)                  :string           not null
#  note(The sender-specified note)                                   :text
#  receiver(The receiver of the transaction)                         :string           not null
#  recipient_type(The type of the recipient - email)                 :string           not null
#  created_at                                                        :datetime         not null
#  updated_at                                                        :datetime         not null
#  bank_account_id(The bank account that the transaction belongs to) :bigint           not null
#
# Indexes
#
#  index_transactions_on_bank_account_id  (bank_account_id)
#
# Foreign Keys
#
#  fk_rails_...  (bank_account_id => bank_accounts.id)
#
require 'rails_helper'

RSpec.describe Transaction, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
