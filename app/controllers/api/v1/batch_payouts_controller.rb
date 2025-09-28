module Api
  module V1
    class BatchPayoutsController < BaseController
      def create
        result = BatchPayoutService.new(batch_payout_params).execute

        if result[:status] == :created
          render json: result[:batch_payout], status: :created
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      end

      private

      def batch_payout_params
        params.permit(:company_name, :company_bic, :company_iban,
                      payouts: [ :amount, :currency, :recipient_name, :recipient_email, :recipient_bic, :recipient_iban, :reason ])
      end
    end
  end
end
