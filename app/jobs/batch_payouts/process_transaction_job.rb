# app/jobs/process_transaction_job.rb
class BatchPayouts::ProcessTransactionJob
  include Sidekiq::Job
  MAX_RETRIES = 5

  sidekiq_options queue: "default",
                  retry: 5,
                  backtrace: true,
                  retry_in: ->(retry_count) { (retry_count ** 2) * 60 }  # Explicit Exponential backoff
  # Helps to navigate the thundering herd problem by spreading out the load

  def perform(transaction_id)
    transaction = Transaction.includes(:bank_account, :batch_payout).find(transaction_id)

    # Skip if already processed & ensures job remains idempotent(i.e., running it multiple times is not an issue)
    return if transaction.status != "pending"

    ActiveRecord::Base.transaction do
      begin
        # You can assume external payout to be successful for now
        success, error_message = make_external_payout(transaction)

        if success
          handle_success(transaction)
        else
          handle_failure(transaction, error_message)
        end
      rescue => e
        Rails.logger.error "Transaction #{transaction_id} failed: #{e.message}"
        raise # Re-raise to trigger Sidekiq retry this is for unexpected errors like Network Timeout, etc.
      end
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Transaction #{transaction_id} not found: #{e.message}"
    # Don't retry if record doesn't exist
    raise Sidekiq::Job::Interrupted
  end

  private

  def handle_success(transaction)
    transaction.update!(status: "SUCCESS")
    transaction.bank_account.process_transaction_success!(transaction.amount_cents)
    update_batch_payout_status(transaction.batch_payout, true)
  end

  def handle_failure(transaction, error_message = nil)
    transaction.increment!(:retry_count)

    if transaction.retry_count >= MAX_RETRIES
      transaction.update!(
        status: "FAILED",
        last_error: error_message
      )
      transaction.bank_account.release_reserved_funds!(transaction.amount_cents)
      update_batch_payout_status(transaction.batch_payout, false)
    else
      retry_delay = calculate_retry_delay(transaction.retry_count)
      transaction.update!(
        last_error: error_message,
        next_retry_at: retry_delay.from_now
      )
      BatchPayouts::ProcessTransactionJob.perform_in(retry_delay, transaction.id)
    end
  end

  def calculate_retry_delay(retry_count)
    # Exponential backoff: 2min, 4min, 8min, 16min, 32min
    # Helps to navigate the thundering herd problem by spreading out the load
    case retry_count
    when 1 then (2 ** retry_count).minutes  # 2 minutes
    when 2 then (2 ** retry_count).minutes  # 4 minutes
    when 3 then (2 ** retry_count).minutes  # 8 minutes
    when 4 then (2 ** retry_count).minutes  # 16 minutes
    when 5 then (2 ** retry_count).minutes  # 32 minutes
    else
      raise ArgumentError, "Unexpected retry_count: #{retry_count}. Should not exceed MAX_RETRIES (#{MAX_RETRIES})"
    end
  end

  def make_external_payout(transaction)
    # Simulate PayPal API call
    error_message = nil
    [ true, error_message ] # for now, assume success as this is a contrived example as part of a code exercise
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
    if batch_payout.transactions.pluck(:status).all? { |s| s == "success" }
      "SUCCESS"
    else
      "DENIED"
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
