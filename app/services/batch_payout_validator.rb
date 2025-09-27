class BatchPayoutValidator
  attr_reader :errors

  def initialize(params)
    @company_name = params[:company_name]
    @company_bic = params[:company_bic]
    @company_iban = params[:company_iban]
    @payouts = params[:payouts]
    @errors = []
  end

  def valid?
    @errors.clear

    validate_required_fields
    validate_payouts_structure if @errors.empty?

    @errors.empty?
  end

  private

  def validate_required_fields
    @errors << "company_name is required" if @company_name.blank?
    @errors << "company_bic is required" if @company_bic.blank?
    @errors << "company_iban is required" if @company_iban.blank?
    @errors << "payouts is required" if @payouts.blank?
  end

  def validate_payouts_structure
    return if @payouts.blank?

    @payouts.each_with_index do |transfer, index|
      validate_transfer_fields(transfer, index)
      validate_amount_format(transfer, index)
    end
  end

  def validate_transfer_fields(transfer, index)
    required_fields = [ :amount, :currency, :recipient_name, :recipient_bic, :recipient_iban, :recipient_email ]

    required_fields.each do |field|
      if transfer[field].blank?
        @errors << "Transfer ##{index + 1}: #{field} is required"
      end
    end

    supported_currencies = %w[EUR INR USD JPY SGD GBP]
    if transfer[:currency].present? && !supported_currencies.include?(transfer[:currency])
      @errors << "Transfer ##{index + 1}: Currency must be one of: #{supported_currencies.join(', ')}"
    end
  end

  def validate_amount_format(transfer, index)
    return if transfer[:amount].blank?

    amount = transfer[:amount].to_s

    begin
      amount_decimal = BigDecimal(amount)
      if amount_decimal <= 0
        @errors << "Transfer ##{index + 1}: Amount must be positive"
      end
    rescue ArgumentError
      @errors << "Transfer ##{index + 1}: Invalid amount format"
    end
  end
end
