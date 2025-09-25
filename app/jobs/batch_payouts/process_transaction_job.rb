# app/jobs/process_transaction_job.rb
class BatchPayouts::ProcessTransactionJob
  include Sidekiq::Job

  # Configure Sidekiq options
  sidekiq_options queue: "default",
                  retry: 5,
                  backtrace: true,
                  dead: true,  # Send to dead queue after retries exhausted
                  retry_in: ->(retry_count) { (retry_count ** 2) * 60 }  # Exponential backoff
  # Helps to navigate the thundering herd problem by spreading out the load

  def perform(transaction_id)
    transaction = Transaction.includes(:bank_account, :batch_payout).find(transaction_id)

    # Skip if already processed
    return if transaction.status != "PENDING"

    ActiveRecord::Base.transaction do
      begin
        # You can assume external payout to be successful for now
        success = make_external_payout(transaction)

        if success
          handle_success(transaction)
        else
          handle_failure(transaction)
        end
      rescue => e
        Rails.logger.error "Transaction #{transaction_id} failed: #{e.message}"
        handle_failure(transaction, e.message)
        raise # Re-raise to trigger Sidekiq retry
      end
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Transaction #{transaction_id} not found: #{e.message}"
    # Don't retry if record doesn't exist
    raise Sidekiq::JobRetry::Skip
  end

  private

  def handle_success(transaction)
    transaction.update!(status: "SUCCESS")
    transaction.bank_account.process_transaction_success!(transaction.amount_cents)
    update_batch_payout_status(transaction.batch_payout, true)
  end

  def handle_failure(transaction, error_message = nil)
    transaction.update!(
      status: "FAILED",
      last_error: error_message
    )
    transaction.bank_account.release_reserved_funds!(transaction.amount_cents)
    update_batch_payout_status(transaction.batch_payout, false)
  end

  def make_external_payout(transaction)
    # Simulate PayPal API call

    true # for now, assume success
  end

  def update_batch_payout_status(batch_payout, success)
    batch_payout.with_lock do
      if success
        batch_payout.successful_count += 1
      else
        batch_payout.failed_count += 1
      end
      batch_payout.pending_count -= 1

      # Check if processing is complete
      if batch_payout.pending_count == 0
        batch_payout.completed_at = Time.current

        # Determine final status
        batch_payout.status = determine_final_status(batch_payout)

        # Close the batch and release any remaining reserved funds
        if should_close_batch?(batch_payout)
          close_batch(batch_payout)
        end
      end

      batch_payout.save!
    end
  end

  def determine_final_status(batch_payout)
    if batch_payout.failed_count == 0
      "SUCCESS"
    elsif batch_payout.successful_count == 0
      "FAILED"
    else
      "PARTIAL_SUCCESS"
    end
  end

  def should_close_batch?(batch_payout)
    # Close when all transactions are finalized
    batch_payout.pending_count == 0
  end

  def close_batch(batch_payout)
    batch_payout.closed_at = Time.current
    # The status is already set by determine_final_status
    # No need to override with 'CLOSED' - keep the meaningful status
  end
end
