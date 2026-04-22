# frozen_string_literal: true

class WalletUpdateService
  Result = Struct.new(:success?, :wallet, :error, :details, :status, keyword_init: true)

  def initialize(user:, wallet_id:, params:)
    @user = user
    @wallet_id = wallet_id
    @params = params
  end

  def call
    wallet = find_wallet
    apply_updates!(wallet)

    Result.new(success?: true, wallet: wallet, status: :ok)
  rescue ActiveRecord::RecordNotFound
    Result.new(success?: false, error: 'Wallet not found', status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false,
               wallet: e.record,
               error: e.message,
               details: e.record.errors.full_messages,
               status: :unprocessable_entity)
  end

  private

  def find_wallet
    @user.wallets.find(@wallet_id)
  end

  def apply_updates!(wallet)
    wallet.update!(@params)
  end
end
