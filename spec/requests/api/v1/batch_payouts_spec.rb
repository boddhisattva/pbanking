require 'rails_helper'

RSpec.describe "Api::V1::BatchPayouts", type: :request do
  describe "POST /api/v1/batch_payouts" do
    let(:business_account) { create(:business_account) }
    let(:bank_account) { create(:bank_account, business_account: business_account, balance_cents: 10_000_000) }

    let(:valid_params) do
      {
        company_name: "Test Company",
        company_bic: "BBRCIHGTXXX",
        company_iban: bank_account.iban,
        payouts: [
          {
            amount: "20.25",
            currency: "EUR",
            recipient_name: "Marcus Roger",
            recipient_email: "marcus@roger.com",
            recipient_bic: "SELYFRXWERW",
            recipient_iban: "SE7280000810340009783242",
            reason: "For your services"
          },
          {
            amount: "100.50",
            currency: "EUR",
            recipient_name: "Ernest Hemingway",
            recipient_email: "ernesthemingway@hemingway.com",
            recipient_bic: "WLPPQRST",
            recipient_iban: "HU93116000060000000012345676",
            reason: "For lessons on life"
          }
        ]
      }
    end

    let(:insufficient_funds_params) do
      {
        company_name: "Test Company",
        company_bic: "BBRCIHGTXXX",
        company_iban: bank_account.iban,
        payouts: [
          {
            amount: "999999999.99",
            currency: "EUR",
            recipient_name: "Marcus Roger",
            recipient_email: "marcus@roger.com",
            recipient_bic: "SELYFRXWERW",
            recipient_iban: "SE7280000810340009783242",
            reason: "For your services"
          }
        ]
      }
    end

    context "when the business account has sufficient funds" do
      before { bank_account }

      it "creates a batch payout with transactions and returns 201", :sidekiq_inline do
        expect {
          post "/api/v1/batch_payouts", params: valid_params, as: :json
        }.to change(BatchPayout, :count).by(1)
          .and change(Transaction, :count).by(2)

        expect(response).to have_http_status(:created)
        batch_payout = BatchPayout.last

        json_response = JSON.parse(response.body)
        expect(json_response["id"]).to be_present
        expect(json_response["status"]).to eq("success")

        expect(batch_payout.business_account).to eq(business_account)
        expect(batch_payout.transactions.count).to eq(2)

        first_transaction = batch_payout.transactions.first
        expect(first_transaction.amount_cents).to eq(2025)
        expect(first_transaction.receiver).to eq("marcus@roger.com")
        expect(first_transaction.status).to eq("success")


        expect(bank_account.reload.balance_cents).to eq(9987925)
        expect(bank_account.reserved_amount_cents).to eq(0)
      end

      it "enqueues the correct Sidekiq jobs for async processing" do
        post "/api/v1/batch_payouts", params: valid_params, as: :json

        batch_payout = BatchPayout.last

        expect(BatchPayouts::ProcessBatchPayoutJob).to have_enqueued_sidekiq_job(batch_payout.id)
      end
    end

    context "when the business account has insufficient funds" do
      before { bank_account.update!(balance_cents: 1000) }

      it "does not create any records and returns unprocessable entity" do
        expect {
          post "/api/v1/batch_payouts", params: insufficient_funds_params, as: :json
        }.not_to change(BatchPayout, :count)

        expect(response).to have_http_status(:unprocessable_content)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("Insufficient funds")

        expect(bank_account.reload.balance_cents).to eq(1000)
      end

      it "does not enqueue any Sidekiq jobs when funds are insufficient" do
        # Clear any existing jobs
        Sidekiq::Worker.clear_all

        post "/api/v1/batch_payouts", params: insufficient_funds_params, as: :json

        # No batch payout job should be enqueued
        expect(BatchPayouts::ProcessBatchPayoutJob.jobs.size).to eq(0)

        # Verify reserved amount remains unchanged
        expect(bank_account.reload.reserved_amount_cents).to eq(0)
      end
    end

    context "when the bank account does not exist" do
      let(:invalid_iban_params) do
        {
          company_name: "Some Company",
          company_bic: "BBRCIHGTXXX",
          company_iban: "INVALID_IBAN",
          payouts: [
            {
              amount: "20.25",
              currency: "EUR",
              recipient_name: "Marcus Roger",
              recipient_email: "marcus@roger.com",
              recipient_bic: "SELYFRXWERW",
              recipient_iban: "SE7280000810340009783242",
              reason: "For your services"
            }
          ]
        }
      end

      it "returns unprocessable entity with error message" do
        expect {
          post "/api/v1/batch_payouts", params: invalid_iban_params, as: :json
        }.not_to change(BatchPayout, :count)

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("Couldn't find BankAccount")
      end

      it "does not enqueue any Sidekiq jobs when bank account doesn't exist" do
        Sidekiq::Worker.clear_all

        post "/api/v1/batch_payouts", params: invalid_iban_params, as: :json

        expect(BatchPayouts::ProcessBatchPayoutJob.jobs.size).to eq(0)

        expect(Transaction.count).to eq(0)
      end
    end
  end
end
