class AddRetryCountToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :retry_count, :integer, default: 0, null: false, comment: 'number of times the transaction has been retried'
  end
end
