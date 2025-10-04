module BatchPayouts
  class ProcessBatchPayoutJob
    include Sidekiq::Job

    sidekiq_options queue: "critical",
                    retry: 3,
                    backtrace: true

    def perform(batch_payout_id)
      batch_payout = BatchPayout.find(batch_payout_id)

      batch_payout.transactions.find_each do |transaction|
        BatchPayouts::ProcessTransactionJob.perform_async(transaction.id)
      end
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "BatchPayout #{batch_payout_id} not found: #{e.message}"
      # Don't retry if record doesn't exist
      raise Sidekiq::Job::Interrupted
    end
  end
end
