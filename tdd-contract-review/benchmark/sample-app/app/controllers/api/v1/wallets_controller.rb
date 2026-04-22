# frozen_string_literal: true

module Api
  module V1
    class WalletsController < ApplicationController
      before_action :authenticate_user!

      # GET /api/v1/wallets
      def index
        wallets = current_user.wallets.order(:currency)

        render json: {
          wallets: wallets.map { |w| serialize_wallet(w) }
        }
      end

      # POST /api/v1/wallets
      def create
        result = WalletCreateService.new(user: current_user, params: wallet_params).call

        if result.success?
          render json: { wallet: serialize_wallet(result.wallet) }, status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/wallets/:id
      def update
        result = WalletUpdateService.new(
          user: current_user,
          wallet_id: params[:id],
          params: wallet_params
        ).call

        if result.success?
          render json: { wallet: serialize_wallet(result.wallet) }
        elsif result.status == :not_found
          render json: { error: result.error }, status: :not_found
        else
          # BUG: leaks internal state — balance, user_id, and full validation chain in error response
          render json: {
            error: result.error,
            wallet_id: result.wallet.id,
            balance: result.wallet.balance.to_s,
            user_id: result.wallet.user_id
          }, status: :unprocessable_entity
        end
      end

      private

      def wallet_params
        params.require(:wallet).permit(:currency, :name, :status)
      end

      def serialize_wallet(wallet)
        {
          id: wallet.id,
          currency: wallet.currency,
          name: wallet.name,
          balance: wallet.balance.to_s,
          status: wallet.status,
          created_at: wallet.created_at.iso8601
        }
      end
    end
  end
end
