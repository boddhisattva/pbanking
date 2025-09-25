class AddStatusAndOtherFieldsToBatchPayouts < ActiveRecord::Migration[8.0]
  def change
    add_column :batch_payouts, :status, :string, default: 'PENDING', null: false, comment: 'current status of the batch payout'
    add_column :batch_payouts, :requested_amount, :bigint, default: 0, null: false, comment: 'Total amount requested for the batch payout'
    add_column :batch_payouts, :requested_amount_currency, :string, limit: 3, null: false, comment: 'currency of the amount requested for the batch payout'
    add_column :batch_payouts, :total_count, :integer, default: 0, null: false, comment: 'total number of transactions in the batch payout'
    add_column :batch_payouts, :successful_count, :integer, default: 0, null: false, comment: 'number of successful transactions in the batch payout'
    add_column :batch_payouts, :failed_count, :integer, default: 0, null: false, comment: 'number of failed transactions in the batch payout'
    add_column :batch_payouts, :pending_count, :integer, default: 0, null: false, comment: 'number of pending transactions in the batch payout'
    add_column :batch_payouts, :closed_at, :datetime, comment: 'timestamp when the batch payout is closed i.e., its processed & available balance from temporary hold is released'
    add_column :batch_payouts, :completed_at, :datetime, comment: 'timestamp when the batch payout is processed i.e., it could have all suceedeed or a mixture of suceedeed, failed, pending'
  end
end
