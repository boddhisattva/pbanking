class AddBatchPayoutAndStatusToTransactions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :transactions, :batch_payout, null: true, index: {algorithm: :concurrently}
    add_column :transactions, :status, :string, default: "pending"
  end
end
