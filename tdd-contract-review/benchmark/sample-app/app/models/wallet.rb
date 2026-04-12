# frozen_string_literal: true

class Wallet < ApplicationRecord
  belongs_to :user
  has_many :transactions, dependent: :restrict_with_error

  enum :status, { active: 'active', suspended: 'suspended', closed: 'closed' }

  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP BTC ETH] }
  validates :currency, uniqueness: { scope: :user_id, message: 'wallet already exists for this currency' }
  validates :name, presence: true, length: { maximum: 100 }
  validates :balance, numericality: { greater_than_or_equal_to: 0 }

  before_create :set_default_balance

  def deposit!(amount)
    raise ArgumentError, 'Amount must be positive' unless amount.positive?
    raise 'Wallet is not active' unless active?

    with_lock do
      update!(balance: balance + amount)
    end
  end

  def withdraw!(amount)
    raise ArgumentError, 'Amount must be positive' unless amount.positive?
    raise 'Wallet is not active' unless active?
    raise 'Insufficient balance' if balance < amount

    with_lock do
      update!(balance: balance - amount)
    end
  end

  private

  def set_default_balance
    self.balance ||= 0
  end
end
