require 'rails_helper'

RSpec.describe BatchPayoutValidator do
  subject(:validator) { described_class.new(params) }

  let(:valid_params) do
    {
      company_name: "Purposeful Life EU-Inc",
      company_bic: 'BNPAFRPP',
      company_iban: 'FR1420041010050500013M02606',
      payouts: [
        {
          "amount": "20.25",
          "currency": "EUR",
          "recipient_name": "Marcus Roger",
          "recipient_email": "marcus@roger.com",
          "recipient_bic": "SELYFRXWERW",
          "recipient_iban": "SE7280000810340009783242",
          "reason": "For your services"
        }
      ]
    }
  end

  let(:params) { valid_params }

  describe '#valid?' do
    context 'with all valid params' do
      it 'returns true with no errors' do
        expect(validator.valid?).to be true
        expect(validator.errors).to be_empty
      end
    end

    context 'required field validation' do
      shared_examples 'required field' do |field|
        it "validates #{field} presence" do
          params[field] = nil
          expect(validator.valid?).to be false
          expect(validator.errors).to include("#{field} is required")
        end
      end

      include_examples 'required field', :company_name
      include_examples 'required field', :company_bic
      include_examples 'required field', :company_iban
      include_examples 'required field', :payouts
    end

    context 'when multiple required fields are missing' do
      it 'collects all validation errors' do
        params[:company_bic] = ''
        params[:company_iban] = ''
        params[:company_name] = ''
        params[:payouts] = []

        validator.valid?
        expect(validator.errors).to include(
          'company_name is required',
          'company_bic is required',
          'company_iban is required',
          'payouts is required'
        )
      end
    end
  end

  describe 'credit transfer validation' do
    shared_examples 'required transfer field' do |field|
      it "validates #{field} and returns appropriate error" do
        params[:payouts][0][field] = nil
        expect(validator.valid?).to be false
        expect(validator.errors).to include("Transfer #1: #{field} is required")
      end
    end

    include_examples 'required transfer field', :amount
    include_examples 'required transfer field', :currency
    include_examples 'required transfer field', :recipient_name
    include_examples 'required transfer field', :recipient_email
    include_examples 'required transfer field', :recipient_bic
    include_examples 'required transfer field', :recipient_iban

    context 'amount validation' do
      it 'rejects zero amounts' do
        params[:payouts][0][:amount] = '0'
        expect(validator.valid?).to be false
        expect(validator.errors).to include('Transfer #1: Amount must be positive')
      end

      it 'rejects negative amounts' do
        params[:payouts][0][:amount] = '-50.00'
        expect(validator.valid?).to be false
        expect(validator.errors).to include('Transfer #1: Amount must be positive')
      end

      it 'validates amount format' do
        params[:payouts][0][:amount] = 'not_a_number'
        expect(validator.valid?).to be false
        expect(validator.errors).to include('Transfer #1: Invalid amount format')
      end
    end

    context 'currency validation' do
      shared_examples 'accepts currency' do |currency|
        it "accepts #{currency} currency" do
          params[:payouts][0][:currency] = currency
          expect(validator.valid?).to be true
        end
      end

      include_examples 'accepts currency', 'EUR'
      include_examples 'accepts currency', 'INR'
      include_examples 'accepts currency', 'USD'
      include_examples 'accepts currency', 'JPY'
      include_examples 'accepts currency', 'SGD'
      include_examples 'accepts currency', 'GBP'

      it 'rejects unsupported currencies' do
        params[:payouts][0][:currency] = 'INVALID'
        expect(validator.valid?).to be false
        expect(validator.errors).to include('Transfer #1: Currency must be one of: EUR, INR, USD, JPY, SGD, GBP')
      end
    end

    context 'with multiple transfers having errors' do
      it 'collects errors from all transfers' do
        params[:payouts] = [
          {
            amount: '-10',
            currency: 'INVALID',
            recipient_name: 'Alice',
            recipient_bic: 'BIC1',
            recipient_iban: 'IBAN1'
          },
          {
            amount: 'invalid',
            currency: 'EUR',
            recipient_name: '',
            recipient_bic: 'BIC2',
            recipient_iban: 'IBAN2'
          }
        ]

        validator.valid?
        expect(validator.errors).to include(
          'Transfer #1: Currency must be one of: EUR, INR, USD, JPY, SGD, GBP',
          'Transfer #1: Amount must be positive',
          'Transfer #2: recipient_name is required',
          'Transfer #2: Invalid amount format'
        )
      end
    end

    context 'optional fields' do
      it 'allows missing reason' do
        params[:payouts][0][:reason] = nil
        expect(validator.valid?).to be true
        expect(validator.errors).to be_empty
      end
    end
  end

  # Todo: to review from below
  describe '#validate_sufficient_funds' do
    let(:bank_account) { FactoryBot.build(:bank_account, balance_cents: 50000) }

    it 'validates fund availability' do
      validator.validate_sufficient_funds(bank_account, 30000)
      expect(validator.errors).to be_empty

      validator.validate_sufficient_funds(bank_account, 50000)
      expect(validator.errors).to be_empty

      validator.validate_sufficient_funds(bank_account, 60000)
      expect(validator.errors).to include('Insufficient funds. Required: 60000 cents, Available: 50000 cents')
    end
  end

  describe 'error clearing behavior' do
    it 'clears previous errors on revalidation' do
      params[:company_bic] = nil
      validator.valid?
      expect(validator.errors).not_to be_empty

      params[:company_bic] = 'ABCIDEFXX'
      new_validator = described_class.new(params)
      new_validator.valid?
      expect(new_validator.errors).to be_empty
    end
  end
end