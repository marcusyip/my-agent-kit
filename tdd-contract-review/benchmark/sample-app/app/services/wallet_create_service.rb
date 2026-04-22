# frozen_string_literal: true

class WalletCreateService
  Result = Struct.new(:success?, :wallet, :error, :details, keyword_init: true)

  def initialize(user:, params:)
    @user = user
    @params = params
  end

  def call
    wallet = build_wallet
    wallet.save!

    Result.new(success?: true, wallet: wallet)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false,
               wallet: e.record,
               error: e.record.errors.full_messages.join(', '),
               details: e.record.errors.full_messages)
  end

  private

  def build_wallet
    @user.wallets.build(@params)
  end
end
