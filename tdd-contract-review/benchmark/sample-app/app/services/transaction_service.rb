# frozen_string_literal: true

class TransactionService
  Result = Struct.new(:success?, :transaction, :error, :details, keyword_init: true)

  def initialize(user:, wallet:, params:)
    @user = user
    @wallet = wallet
    @params = params
  end

  def call
    validate_wallet_active!
    validate_currency_match!
    validate_sufficient_balance!

    transaction = build_transaction
    transaction.save!

    deduct_balance!(transaction)

    if transaction.payment?
      charge_payment_gateway(transaction)
    end

    Result.new(success?: true, transaction: transaction)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: 'Validation failed', details: e.record.errors.full_messages)
  rescue WalletInactiveError => e
    Result.new(success?: false, error: e.message, details: ['Wallet must be active'])
  rescue CurrencyMismatchError => e
    Result.new(success?: false, error: e.message, details: ['Currency must match wallet currency'])
  rescue InsufficientBalanceError => e
    Result.new(success?: false, error: e.message,
               details: ["Current balance: #{@wallet.balance}, requested: #{@params[:amount]}"])
  rescue PaymentGateway::ChargeError => e
    Result.new(success?: false, error: 'Payment processing failed', details: [e.message])
  end

  private

  def validate_wallet_active!
    raise WalletInactiveError, 'Wallet is not active' unless @wallet.active?
  end

  def validate_currency_match!
    return if @params[:currency] == @wallet.currency

    raise CurrencyMismatchError, 'Currency does not match wallet'
  end

  def validate_sufficient_balance!
    amount = BigDecimal(@params[:amount].to_s)
    return if @wallet.balance >= amount

    raise InsufficientBalanceError,
          "Insufficient balance (need #{amount}, have #{@wallet.balance})"
  end

  def deduct_balance!(transaction)
    return if transaction.deposit?

    @wallet.withdraw!(transaction.amount)
  end

  def build_transaction
    @user.transactions.build(
      wallet: @wallet,
      amount: @params[:amount],
      currency: @params[:currency],
      description: @params[:description],
      category: @params[:category] || 'transfer',
      status: 'pending'
    )
  end

  def charge_payment_gateway(transaction)
    response = PaymentGateway.charge(
      amount: transaction.amount,
      currency: transaction.currency,
      user_id: @user.id,
      transaction_id: transaction.id
    )

    if response.success?
      transaction.update!(status: 'completed')
    else
      transaction.update!(status: 'failed')
    end
  end

  class WalletInactiveError < StandardError; end
  class CurrencyMismatchError < StandardError; end
  class InsufficientBalanceError < StandardError; end
end
