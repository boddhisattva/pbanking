class BatchPayoutService
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

      business_account = bank_account.business_account
      total_amount_cents = calculate_total_amount_cents

      @validator.validate_sufficient_funds(bank_account, total_amount_cents)

      if @validator.errors.present?
        validation_error_response
      else
        batch_payout = create_batch_payout(business_account)
        create_transactions(batch_payout, bank_account)
        update_bank_account_balance(bank_account)

        { status: :created, batch_payout: batch_payout_response(batch_payout) }
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

  def insufficient_funds_error
    { success: false, error: "Insufficient funds" }
  end

  def create_batch_payout(business_account)
    BatchPayout.create!(business_account: business_account)
  end

  def create_transactions(batch_payout, bank_account)
    @params[:payouts].each do |payout|
      Transaction.create!(
        batch_payout: batch_payout,
        bank_account: bank_account,
        amount_cents: (payout[:amount].to_f * 100).to_i,
        amount_currency: payout[:currency],
        receiver: payout[:recipient_email],
        recipient_type: "EMAIL",
        note: payout[:reason],
        status: "success"
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
      status: "completed"
      # transactions: batch_payout.transactions.map do |transaction|
      #   {
      #     id: transaction.id,
      #     amount: {
      #       cents: transaction.amount_cents/100.0,
      #       currency: transaction.amount_currency
      #     },
      #     receiver: transaction.receiver,
      #     note: transaction.note,
      #     status: transaction.status,
      #     recipient_type: transaction.recipient_type
      #   }
      # end
    }
  end
end
