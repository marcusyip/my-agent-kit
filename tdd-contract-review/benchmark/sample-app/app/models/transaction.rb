# frozen_string_literal: true

class Transaction < ApplicationRecord
  belongs_to :user
  belongs_to :wallet

  enum :status, { pending: 'pending', completed: 'completed', failed: 'failed', reversed: 'reversed' }
  enum :category, {
    transfer: 'transfer',
    payment: 'payment',
    deposit: 'deposit',
    withdrawal: 'withdrawal'
  }

  validates :amount, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 1_000_000 }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP BTC ETH] }
  validates :status, presence: true
  validates :description, length: { maximum: 500 }

  scope :recent, -> { where('created_at > ?', 30.days.ago) }
  scope :by_status, ->(status) { where(status: status) }

  after_create :notify_payment_gateway, if: :payment?

  private

  def notify_payment_gateway
    PaymentGateway.charge(
      amount: amount,
      currency: currency,
      user_id: user_id,
      transaction_id: id
    )
  end
end
