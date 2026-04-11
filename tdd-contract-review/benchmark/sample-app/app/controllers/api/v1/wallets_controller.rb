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
        wallet = current_user.wallets.build(wallet_params)

        if wallet.save
          render json: { wallet: serialize_wallet(wallet) }, status: :created
        else
          render json: { error: wallet.errors.full_messages.join(', ') },
                 status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/wallets/:id
      def update
        wallet = current_user.wallets.find(params[:id])
        wallet.update!(wallet_params)

        render json: { wallet: serialize_wallet(wallet) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Wallet not found' }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
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
