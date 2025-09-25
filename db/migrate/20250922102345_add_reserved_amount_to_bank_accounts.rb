class AddReservedAmountToBankAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_accounts, :reserved_amount_cents, :bigint, default: 0, null: false,
               comment: 'Amount reserved for transactions in proceess/pending e.g., for a batch payout'
  end
end
