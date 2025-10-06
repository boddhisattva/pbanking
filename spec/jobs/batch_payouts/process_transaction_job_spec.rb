require 'rails_helper'

RSpec.describe BatchPayouts::ProcessTransactionJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  subject(:job) { described_class.new }

  let(:business_account) { create(:business_account) }
  let(:batch_payout) do
    create(:batch_payout,
                      business_account: business_account,
                      total_count: 1,
                      pending_count: 1,
                      successful_count: 0,
                      failed_count: 0,
                      status: 'pending')
  end
  let(:bank_account) do
    create(:bank_account,
                      business_account: business_account,
                      balance_cents: 100000,
                      reserved_amount_cents: 5000)
  end
  let(:transaction) do
    create(:transaction,
                      batch_payout: batch_payout,
                      bank_account: bank_account,
                      amount_cents: 5000,
                      status: 'pending')
  end

  describe '#perform' do
    context 'when transaction exists and is pending' do
      context 'when external payout succeeds' do
        before do
          allow(job).to receive(:make_external_payout).and_return(true)
        end


        context 'when transaction is not the last transaction before success' do
          let(:pending_transaction_1) do
            create(:transaction,
                              batch_payout: batch_payout,
                              bank_account: bank_account,
                              amount_cents: 3000,
                              status: 'pending')
          end

          let(:pending_transaction_2) do
            create(:transaction,
                              batch_payout: batch_payout,
                              bank_account: bank_account,
                              amount_cents: 3000,
                              status: 'pending')
          end

          before do
            pending_transaction_1
            pending_transaction_2
            batch_payout.update!(
              total_count: 2,
              pending_count: 2,
              successful_count: 0,
              failed_count: 0
            )
          end

          it 'does not mark batch as completed & updates other batch payout details correctly' do
            job.perform(pending_transaction_1.id)

            batch_payout.reload
            expect(batch_payout.status).to eq('pending')
            expect(batch_payout.closed_at).to be_nil
            expect(batch_payout.completed_at).to be_nil
            expect(batch_payout.failed_count).to eq(0)
            expect(batch_payout.pending_count).to eq(1)
            expect(batch_payout.successful_count).to eq(1)
          end
        end
        it 'updates transaction status to SUCCESS, batch payout appropriately & calls process_transaction_success!' do
          expect_any_instance_of(BankAccount)
            .to receive(:process_transaction_success!)
            .with(5000)

          job.perform(transaction.id)
          expect(transaction.reload.status).to eq('success')

          batch_payout.reload

          expect(batch_payout.successful_count).to eq(1)
          expect(batch_payout.failed_count).to eq(0)
          expect(batch_payout.pending_count).to eq(0)

          expect(batch_payout.completed_at).not_to be_nil
          expect(batch_payout.closed_at).not_to be_nil
          expect(batch_payout.status).to eq('success')
        end

        context 'when update_batch_payout_status fails after transaction success' do
          before do
            allow(job).to receive(:make_external_payout).and_return(true)
            allow_any_instance_of(BatchPayout).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(batch_payout))
          end

          it 'rolls back the entire transaction including transaction status and bank account changes' do
            initial_transaction_status = transaction.status
            initial_bank_balance = bank_account.balance_cents
            initial_bank_reserved = bank_account.reserved_amount_cents

            expect { job.perform(transaction.id) }.to raise_error(ActiveRecord::RecordInvalid)

            transaction.reload
            bank_account.reload

            expect(transaction.status).to eq(initial_transaction_status)
            expect(bank_account.balance_cents).to eq(initial_bank_balance)
            expect(bank_account.reserved_amount_cents).to eq(initial_bank_reserved)
          end
        end
      end

      context 'when external payout fails' do
        before do
          allow(job).to receive(:make_external_payout).and_return(false)
        end

        it 'updates transaction retry count, updates batch payout counters correctly, calls release_reserved_funds!' do
          expect(BatchPayouts::ProcessTransactionJob)
          .to receive(:perform_in)
          .with(2.minutes, transaction.id)

          current_time = Time.current
          travel_to current_time do
            expected_retry_time = 2.minutes.from_now

            expect { job.perform(transaction.id) }.to change { transaction.reload.retry_count }.from(0).to(1)

            transaction.reload
            expect(transaction.status).to eq('pending')
            expect(transaction.next_retry_at).to be_within(1.second).of(expected_retry_time)

            batch_payout.reload
            expect(batch_payout.successful_count).to eq(0)
            expect(batch_payout.pending_count).to eq(1)
            expect(batch_payout.failed_count).to eq(0)
            expect(batch_payout.completed_at).to be_nil
            expect(batch_payout.closed_at).to be_nil
            expect(batch_payout.status).to eq('pending')
          end
        end

        context 'when max retries are exhausted' do
          before do
            # Set transaction to have exhausted all retries
            transaction.update!(retry_count: BatchPayouts::ProcessTransactionJob::MAX_RETRIES)
            allow(job).to receive(:make_external_payout).and_return(false)
          end

          it 'marks transaction as FAILED, releases reserved funds, does not schedule another retry job and updates batch payout appropriately' do
            expect_any_instance_of(BankAccount)
              .to receive(:release_reserved_funds!)
              .with(transaction.amount_cents)

            expect(BatchPayouts::ProcessTransactionJob)
              .not_to receive(:perform_async)

            job.perform(transaction.id)

            transaction.reload
            expect(transaction.status).to eq('failed')
            expect(transaction.retry_count).to eq(BatchPayouts::ProcessTransactionJob::MAX_RETRIES + 1)
            expect(transaction.last_error).to be_nil

            batch_payout.reload

            expect(batch_payout.failed_count).to eq(1)
            expect(batch_payout.successful_count).to eq(0)
            expect(batch_payout.pending_count).to eq(0)

            expect(batch_payout.completed_at).not_to be_nil
            expect(batch_payout.closed_at).not_to be_nil
            expect(batch_payout.status).to eq('denied')
          end

          context 'when update_batch_payout_status fails after marking transaction as FAILED' do
            before do
              allow_any_instance_of(BatchPayout).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(batch_payout))
            end

            it 'rolls back the entire transaction including transaction status and bank account changes' do
              initial_transaction_status = transaction.status
              initial_transaction_retry_count = transaction.retry_count
              initial_bank_balance = bank_account.balance_cents
              initial_bank_reserved = bank_account.reserved_amount_cents

              expect { job.perform(transaction.id) }.to raise_error(ActiveRecord::RecordInvalid)

              transaction.reload
              bank_account.reload

              expect(transaction.status).to eq(initial_transaction_status)
              expect(transaction.retry_count).to eq(initial_transaction_retry_count)
              expect(bank_account.balance_cents).to eq(initial_bank_balance)
              expect(bank_account.reserved_amount_cents).to eq(initial_bank_reserved)
            end
          end
        end
      end

      context 'when external payout raises an exception' do
        let(:error_message) { 'External API error' }

        before do
          allow(job).to receive(:make_external_payout).and_raise(StandardError, error_message)
        end

        it 'logs the error & re-raises the error for Sidekiq to retry the job' do
          expect(Rails.logger).to receive(:error).with(/Transaction #{transaction.id} failed: #{error_message}/)

          expect { job.perform(transaction.id) }.to raise_error(StandardError, error_message)
        end
      end
    end

    context 'when transaction is already processed' do
      before do
        transaction.update!(status: 'success')
      end

      it 'returns early without processing' do
        expect(job).not_to receive(:make_external_payout)
        expect(job).not_to receive(:handle_success)
        expect(job).not_to receive(:handle_failure)

        job.perform(transaction.id)
      end
    end

    context 'when transaction does not exist' do
      let(:non_existent_id) { 999999 }

      it 'logs the error &raises Sidekiq::Job::Interrupted to prevent retries' do
        expect(Rails.logger).to receive(:error).with(/Transaction #{non_existent_id} not found/)

        expect { job.perform(non_existent_id) }
          .to raise_error(Sidekiq::Job::Interrupted)
      end
    end
  end
end
