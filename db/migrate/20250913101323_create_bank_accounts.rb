class CreateBankAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :bank_accounts do |t|
      t.references :business_account, null: false, foreign_key: true, comment: "The business account that the bank account belongs to"
      t.bigint :balance_cents, null: false, default: 0, comment: "The balance of the bank account in cents"
      t.string :iban, null: false, comment: "The IBAN of the bank account"
      t.string :bic, null: false, comment: "The BIC of the bank account"

      t.timestamps
    end
  end
end
