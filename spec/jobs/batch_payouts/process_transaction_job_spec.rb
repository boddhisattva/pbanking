require 'rails_helper'

RSpec.describe BatchPayouts::ProcessTransactionJob, type: :job do
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
          let(:pending_transaction) do
            create(:transaction,
                              batch_payout: batch_payout,
                              bank_account: bank_account,
                              amount_cents: 3000,
                              status: 'pending')
          end

          before do
            pending_transaction

            batch_payout.update!(
              total_count: 2,
              pending_count: 2,
              successful_count: 0,
              failed_count: 0
            )
          end

          it 'does not mark batch as completed' do
            job.perform(transaction.id)

            batch_payout.reload
            expect(batch_payout.status).to eq('pending')
            expect(batch_payout.closed_at).to be_nil
            expect(batch_payout.completed_at).to be_nil
            expect(batch_payout.failed_count).to eq(0)
            expect(batch_payout.pending_count).to eq(1)
            expect(batch_payout.successful_count).to eq(1)
          end
        end
        # TODO: Add test for when transaction is not the last transaction before success
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
      end

      context 'when external payout fails' do
        before do
          allow(job).to receive(:make_external_payout).and_return(false)
        end

        it 'updates transaction retry count, updates batch payout counters correctly, calls release_reserved_funds!' do
          expect(BatchPayouts::ProcessTransactionJob)
          .to receive(:perform_async)
          .with(transaction.id)
          expect { job.perform(transaction.id) }.to change { transaction.reload.retry_count }.from(0).to(1)
          expect(transaction.reload.status).to eq('pending')

          batch_payout.reload

          expect(batch_payout.successful_count).to eq(0)
          expect(batch_payout.pending_count).to eq(1)
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
        end
      end
    end
  end
end
