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
    context 'with valid params and sufficient funds' do
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

      it 'creates transactions with correct receiver details and completed status' do
        result = service.execute
        transaction = Transaction.find_by(receiver: 'alice@example.com')

        # amount_cents = transaction.amount_cents / 100.0
        # expect(transaction.amount_cents).to eq(10050)
        expect(transaction.amount_currency).to eq('EUR')
        expect(transaction.note).to eq('Payment for invoice #123')
        expect(transaction.status).to eq('success')
        expect(transaction.recipient_type).to eq('EMAIL')
      end

      it 'deducts total amount from bank account balance' do
        expect { service.execute }.to change { bank_account.reload.balance_cents }.from(100000).to(84925)
      end

      it 'returns created response' do
        response = service.execute

        expect(response[:status]).to be :created
        expect(response[:batch_payout]).to be_present
        expect(response[:batch_payout][:id]).to eq(BatchPayout.last.id)
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
  end
end
