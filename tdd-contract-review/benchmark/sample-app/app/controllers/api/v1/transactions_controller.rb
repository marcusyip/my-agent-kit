# frozen_string_literal: true

module Api
  module V1
    class TransactionsController < ApplicationController
      before_action :authenticate_user!
      before_action :set_wallet, only: [:create]

      # GET /api/v1/transactions
      def index
        transactions = current_user.transactions
          .includes(:wallet)
          .order(created_at: :desc)

        # Date range filters
        transactions = transactions.where('created_at >= ?', Time.zone.parse(params[:start_date])) if params[:start_date]
        transactions = transactions.where('created_at <= ?', Time.zone.parse(params[:end_date]).end_of_day) if params[:end_date]

        # Status filter
        transactions = transactions.where(status: params[:status]) if params[:status]

        transactions = transactions
          .page(params[:page])
          .per(params[:per_page] || 25)

        render json: {
          transactions: transactions.map { |t| serialize_transaction(t) },
          meta: {
            total: transactions.total_count,
            page: transactions.current_page,
            per_page: transactions.limit_value
          }
        }
      end

      # POST /api/v1/transactions
      def create
        service = TransactionService.new(
          user: current_user,
          wallet: @wallet,
          params: transaction_params
        )

        result = service.call

        if result.success?
          render json: { transaction: serialize_transaction(result.transaction) },
                 status: :created
        else
          render json: { error: result.error, details: result.details },
                 status: :unprocessable_entity
        end
      end

      # GET /api/v1/transactions/:id
      def show
        transaction = current_user.transactions.find(params[:id])

        render json: { transaction: serialize_transaction(transaction) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Transaction not found' }, status: :not_found
      end

      private

      def set_wallet
        @wallet = current_user.wallets.find_by(id: params.dig(:transaction, :wallet_id))

        return if @wallet

        render json: { error: 'Wallet not found' }, status: :unprocessable_entity
      end

      def transaction_params
        params.require(:transaction).permit(:amount, :currency, :wallet_id, :description, :category)
      end

      def serialize_transaction(transaction)
        {
          id: transaction.id,
          amount: transaction.amount.to_s,
          currency: transaction.currency,
          status: transaction.status,
          description: transaction.description,
          category: transaction.category,
          wallet_id: transaction.wallet_id,
          created_at: transaction.created_at.iso8601,
          updated_at: transaction.updated_at.iso8601
        }
      end
    end
  end
end
