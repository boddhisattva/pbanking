class AddBusinessAccountToBatchPayouts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :batch_payouts, :business_account, null: false, index: {algorithm: :concurrently}
  end
end
