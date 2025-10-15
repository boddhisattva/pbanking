require 'rails_helper'

RSpec.describe BatchPayoutService do
  subject(:service) { described_class.new(params) }

  let!(:business_account) { FactoryBot.create(:business_account) }
  let!(:bank_account) { FactoryBot.create(:bank_account, business_account: business_account, balance_cents: 100000, bic: 'BNPAFRPP', iban: 'FR1420041010050500013M02606') }

  let(:valid_params) do
    {
      company_name: "#{business_account.first_name} #{business_account.last_name}",
      company_bic: bank_account.bic,
      company_iban: bank_account.iban,
      payouts: [
        {
          amount: "100.50",
          currency: "EUR",
          recipient_name: "Alice Smith",
          recipient_email: "alice@example.com",
          recipient_bic: "DEUTDEFF",
          recipient_iban: "DE89370400440532013000",
          reason: "Payment for invoice #123"
        },
        {
          amount: "50.25",
          currency: "EUR",
          recipient_name: "Bob Johnson",
          recipient_email: "bob@example.com",
          recipient_bic: "NWBKGB2L",
          recipient_iban: "GB29NWBK60161331926819",
          reason: "Refund"
        }
      ]
    }
  end

  let(:params) { valid_params }

  describe '#execute' do
    context 'with valid params and sufficient funds', :sidekiq_inline do
      it 'creates a batch payout and transactions for each payout' do
        expect { service.execute }
          .to change { BatchPayout.count }.by(1)
          .and change { Transaction.count }.by(2)
      end

      it 'creates transactions with correct amounts in cents' do
        result = service.execute
        expect(result[:status]).to be :created

        transactions = Transaction.all
        expect(transactions[0].amount_cents).to eq(10050)
        expect(transactions[1].amount_cents).to eq(5025)
      end

      it 'creates transactions with correct receiver details and eventual status as success' do
        result = service.execute
        transaction = Transaction.find_by(receiver: 'alice@example.com')

        expect(transaction.amount_cents).to eq(10050)
        expect(transaction.amount_currency).to eq('EUR')
        expect(transaction.note).to eq('Payment for invoice #123')
        expect(transaction.recipient_type).to eq('EMAIL')
        expect(transaction.status).to eq('success')
      end

      it 'deducts total amount from bank account balance' do
        expect { service.execute }.to change { bank_account.reload.balance_cents }.from(100000).to(84925)
      end

      it 'returns created response' do
        response = service.execute

        expect(response[:status]).to be :created
        expect(response[:batch_payout]).to be_present
        expect(response[:batch_payout][:id]).to eq(BatchPayout.last.id)
        expect(response[:batch_payout][:status]).to eq('success')
      end

      it 'executes all operations within a transaction' do
        allow_any_instance_of(BankAccount).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        result = service.execute
        expect(result[:status]).to be :unprocessable_entity
        expect(Transaction.count).to eq(0)
      end
    end


    context 'with insufficient funds' do
      before do
        bank_account.update!(balance_cents: 1000)
      end

      it 'does not create any transactions & returns insufficient funds error' do
        response = nil
        expect { response = service.execute }.to change { Transaction.count }.by(0)
        .and change { bank_account.reload.balance_cents }.by(0)
        expect(response[:status]).to be :unprocessable_entity
        expect(response[:error]).to include('Insufficient funds')
      end
    end

    context 'when bank account not found' do
      before do
        params[:company_iban] = 'NONEXISTENT'
      end

      it 'returns bank account not found error' do
        response = nil
        expect { response = service.execute }.not_to change { Transaction.count }

        expect(response[:status]).to be :unprocessable_entity
        expect(response[:error]).to include("Couldn't find BankAccount")
      end
    end

    context 'with concurrent balance updates', :sidekiq_inline, :concurrent do
      it 'handles concurrent transfers to the same account correctly' do
        initial_balance = bank_account.balance_cents
        transfer_amount_per_request = 10000

        payouts_params = {
          company_name: "#{business_account.first_name} #{business_account.last_name}",
          company_bic: bank_account.bic,
          company_iban: bank_account.iban,
          payouts: [
            {
              amount: '100.00',
              currency: 'EUR',
              recipient_name: 'Test User',
              recipient_email: 'test@example.com',
              recipient_bic: 'DEUTDEFF',
              recipient_iban: 'DE89370400440532013000',
              reason: 'Concurrent test'
            }
          ]
        }

        # PHASE 1: Test concurrent service execution (fund reservation)
        wait_for_service_start = true
        service_results = []

        service_threads = 3.times.map do |i|
          Thread.new do
            # Wait until all threads are created for maximum contention
            true while wait_for_service_start
            ActiveRecord::Base.connection_pool.with_connection do
              service = described_class.new(payouts_params)
              result = service.execute
              service_results << result
            end
          end
        end

        # Start all service threads to execute together/simultaneously
        wait_for_service_start = false
        # upon spawning one or more threads, we use #join to wait for each thread to finish.
        # with the below line, the main thread stops and waits for all threads to finish completely.
        # Simple analogy: ike cooking multiple dishes at once - you can't serve until all are ready.(pizza - dough(shaping & molding it to be circular), sauce(cooking tomatoes), toppings(grating cheese, etc.))
        # In other words: Parent(main thread) waiting for kids(other newly spawned threads) to tie their shoes before leaving the house together (i.e., to complete all transfers)
        # without the below line, the expectations run BEFORE transfers complete
        # Always use join() when you need thread results
        # We don't know how long it will take for the threads to finish so we should ideally wait for all of them.
        # For each thread, wait until it's done
        service_threads.each(&:join)

        # PHASE 2: Test concurrent job processing (balance deduction)
        pending_transactions = Transaction.where(status: "pending")
        wait_for_job_start = true

        job_threads = pending_transactions.map do |transaction|
          Thread.new do
            # Wait for all job threads to be ready
            true while wait_for_job_start
            ActiveRecord::Base.connection_pool.with_connection do
              BatchPayouts::ProcessTransactionJob.new.perform(transaction.id)
            end
          end
        end

        # Start all job threads simultaneously to test job-level concurrency
        wait_for_job_start = false
        job_threads.each(&:join)

        bank_account.reload
        successful_transfers_count = service_results.count { |r| r[:status] == :created }

        expected_balance = initial_balance - (transfer_amount_per_request * successful_transfers_count)


        expect(bank_account.balance_cents).to eq(expected_balance)
        expect(Transaction.count).to eq(successful_transfers_count)
        expect(BatchPayout.count).to eq(3)
        expect(Transaction.all.pluck(:status).uniq).to eq([ 'success' ])

        # Additional concurrency verification
        expect(successful_transfers_count).to eq(3) # All should succeed with sufficient funds
        expect(bank_account.reserved_amount_cents).to eq(0) # All reserved funds released
      end

      it 'handles race conditions with multiple concurrent transfer requests and limited balance in bank account' do
        bank_account.update!(balance_cents: 30000)

        payout_params = {
          company_name: "#{business_account.first_name} #{business_account.last_name}",
          company_bic: bank_account.bic,
          company_iban: bank_account.iban,
          payouts: [
            {
              amount: '100.00',
              currency: 'EUR',
              recipient_name: 'Race Test',
              recipient_email: 'race@example.com',
              recipient_bic: 'DEUTDEFF',
              recipient_iban: 'DE89370400440532013000',
              reason: 'Testing race condition'
            }
          ]
        }

        # PHASE 1: Test concurrent service execution with limited balance
        # 4 threads try to reserve 10,000 each, but only 30,000 available
        wait_for_service_start = true
        service_results = []

        service_threads = 4.times.map do |i|
          Thread.new do
            # Wait until all threads are created for maximum contention
            true while wait_for_service_start
            ActiveRecord::Base.connection_pool.with_connection do
              service = described_class.new(payout_params)
              result = service.execute
              service_results << result
            end
          end
        end

        # Start all service threads simultaneously
        wait_for_service_start = false
        service_threads.each(&:join)

        # PHASE 2: Test concurrent job processing for successful transactions
        # Process all pending transactions concurrently to test job-level locking
        pending_transactions = Transaction.where(status: "pending")
        wait_for_job_start = true

        job_threads = pending_transactions.map do |transaction|
          Thread.new do
            # Wait for all job threads to be ready
            true while wait_for_job_start
            ActiveRecord::Base.connection_pool.with_connection do
              BatchPayouts::ProcessTransactionJob.new.perform(transaction.id)
            end
          end
        end

        # Start all job threads simultaneously to test job-level concurrency
        wait_for_job_start = false
        job_threads.each(&:join)

        # PHASE 3: Verify results
        successful_transfers = service_results.select { |r| r[:status] == :created }
        failed_transfers = service_results.select { |r| r[:status] == :unprocessable_entity }

        expect(successful_transfers.count).to eq(3)
        expect(failed_transfers.count).to eq(1)
        expect(failed_transfers.first[:error]).to include('Insufficient funds')

        bank_account.reload
        expect(bank_account.balance_cents).to eq(0)
        expect(bank_account.reserved_amount_cents).to eq(0)
        expect(Transaction.count).to eq(3)
        expect(Transaction.all.pluck(:status).uniq).to eq([ 'success' ])
      end
    end
  end
end
