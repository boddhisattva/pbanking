class CreateBatchPayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_payouts do |t|
      t.timestamps
    end
  end
end
