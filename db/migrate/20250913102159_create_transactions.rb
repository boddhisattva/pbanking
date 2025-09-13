class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :bank_account, null: false, foreign_key: true, comment: "The bank account that the transaction belongs to"
      t.string :recipient_type, null: false, comment: "The type of the recipient - email"
      t.string :receiver, null: false, comment: "The receiver of the transaction"
      t.bigint :amount_cents, null: false, comment: "The amount of the transaction in cents"
      t.string :amount_currency, null: false, comment: "The currency of the transaction"
      t.text :note, comment: "The sender-specified note"

      t.timestamps
    end
  end
end
