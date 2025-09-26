class BatchPayoutService
  DEFAULT_CURRENCY = "EUR"

  def initialize(params)
    @params = params
    @validator = BatchPayoutValidator.new(params)
  end

  def execute
    return validation_error_response unless @validator.valid?

    bank_account = find_bank_account_by_iban!

    result = bank_account.with_lock do
      # to get the latest value of the current amount left in the bank account
      # especially handy in case of concurrent payout requests
      bank_account.reload

      total_amount_cents = calculate_total_amount_cents

      business_account = bank_account.business_account

      @validator.validate_sufficient_funds(bank_account, total_amount_cents)

      if @validator.errors.present?
        validation_error_response
      else
        bank_account.reserve_funds!(total_amount_cents)
        batch_payout = create_batch_payout(business_account, total_amount_cents)
        # CONTINUE from here post lunch
        create_transactions_as_pending_initially(batch_payout, bank_account)
        # update_bank_account_balance(bank_account)
        BatchPayouts::ProcessBatchPayoutJob.perform_async(batch_payout.id)

        { status: :created, batch_payout: batch_payout_response(batch_payout.reload) }
      end
    end

    result
  rescue StandardError => e
    { status: :unprocessable_entity, error: e.message }
  end

  private

  def validation_error_response
    { success: false, error: @validator.errors.join(", ") }
  end

  def calculate_total_amount_cents
    @params[:payouts].sum do |transfer|
      amount_in_euros = BigDecimal(transfer[:amount].to_s)
      (amount_in_euros * 100).to_i
    end
  end

  def find_bank_account_by_iban!
    BankAccount.find_by!(iban: @params[:company_iban])
  end

  def insufficient_funds_error(available = nil, required = nil)
    { success: false, error: "Insufficient funds" }
  end

  def create_batch_payout(business_account, total_amount_cents)
    total_payouts_count = @params[:payouts].size
    # BatchPayout.create!(business_account: business_account)
    BatchPayout.create!(
      business_account: business_account,
      status: "PENDING",
      requested_amount: total_amount_cents,
      requested_amount_currency: DEFAULT_CURRENCY, # default to EUR or take dynamically from params
      total_count: total_payouts_count,
      pending_count: total_payouts_count,
      successful_count: 0,
      failed_count: 0
    )
  end

  def create_transactions_as_pending_initially(batch_payout, bank_account)
    @params[:payouts].each do |payout|
      Transaction.create!(
        batch_payout: batch_payout,
        bank_account: bank_account,
        amount_cents: (payout[:amount].to_f * 100).to_i,
        amount_currency: payout[:currency],
        receiver: payout[:recipient_email],
        recipient_type: "EMAIL",
        note: payout[:reason],
        status: "PENDING"
      )
    end
  end

  def update_bank_account_balance(bank_account)
    total_amount = calculate_total_amount_cents
    bank_account.update!(balance_cents: bank_account.balance_cents - total_amount)
  end

  def batch_payout_response(batch_payout)
    {
      id: batch_payout.id,
      business_account_id: batch_payout.business_account_id,
      status: batch_payout.status
    }
  end
end
