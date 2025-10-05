class AddNextRetryAtToTransactions < ActiveRecord::Migration[8.0]
  def change
     add_column :transactions, :next_retry_at, :datetime, comment: 'Timestamp when a failed transaction should be retried'
  end
end
