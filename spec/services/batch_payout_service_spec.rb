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

    # continue review from here & main key goal is to make sure add remaining specs later

    # first priority is concurrency passes that's really key
    context 'with insufficient funds' do
      before do
        bank_account.update!(balance_cents: 1000)
      end

      it 'does not create any transactions & returns insufficient funds error' do
        response = nil
        expect { response = service.execute }.to change { Transaction.count }.by(0)
        .and change { bank_account.reload.balance_cents }.by(0)
        expect(response[:success]).to be false
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

    context 'with concurrent balance updates' do
      it 'uses pessimistic locking for balance update' do
        expect_any_instance_of(BankAccount).to receive(:with_lock).and_call_original

        service.execute
      end

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
        wait_for_start = true

        results = []
        threads = 3.times.map do |i|
          Thread.new do
            # below line is to wait until all threads are created
            true while wait_for_start # this allows to have high contention among different threads
            ActiveRecord::Base.connection_pool.with_connection do
              service = described_class.new(payouts_params)
              result = service.execute
              results << result
            end
          end
        end

        # below line is to allow all threads to start execution together(i.e., to replicate simultaneous execution/access)
        wait_for_start = false

        # upon spawning one or more threads, we use #join to wait for each thread to finish.
        # with the below line, the main thread stops and waits for all threads to finish completely.
        # Simple analogy: ike cooking multiple dishes at once - you can't serve until all are ready.(pizza - dough(shaping & molding it to be circular), sauce(cooking tomatoes), toppings(grating cheese, etc.))
        # In other words: Parent(main thread) waiting for kids(other newly spawned threads) to tie their shoes before leaving the house together (i.e., to complete all transfers)
        # without the below line, the expectations run BEFORE transfers complete
        # Always use join() when you need thread results
        # We don't know how long it will take for the threads to finish so we should ideally wait for all of them.
        # For each thread, wait until it's done
        threads.each(&:join)

        bank_account.reload

        successful_transfers = results.count { |r| r[:status] == :created }
        expected_balance = initial_balance - (transfer_amount_per_request * successful_transfers)

        expect(bank_account.balance_cents).to eq(expected_balance)
        expect(Transaction.count).to eq(successful_transfers)
        expect(BatchPayout.count).to eq(3)
        expect(Transaction.all.pluck(:status).uniq).to eq([ 'success' ])
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

        wait_for_start = true

        results = []
        threads = 4.times.map do |i|
          Thread.new do
            true while wait_for_start
            ActiveRecord::Base.connection_pool.with_connection do
              service = described_class.new(payout_params)
              result = service.execute
              results << result
            end
          end
        end
        wait_for_start = false

        threads.each(&:join)

        successful_transfers = results.select { |r| r[:status] == :created }
        failed_transfers = results.select { |r| r[:success] == false }

        expect(successful_transfers.count).to eq(3)
        expect(failed_transfers.count).to eq(1)
        expect(failed_transfers.first[:error]).to include('Insufficient funds')

        bank_account.reload
        expect(bank_account.balance_cents).to eq(0)
        expect(Transaction.count).to eq(3) # 3 successful batch payouts with 1 transaction each
        expect(Transaction.all.pluck(:status).uniq).to eq([ 'success' ])
      end
    end
  end
end
