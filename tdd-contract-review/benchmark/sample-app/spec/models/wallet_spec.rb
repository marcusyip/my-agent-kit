# frozen_string_literal: true

# Intentional gaps for benchmark:
# - deposit!/withdraw! tested but missing concurrent access scenario
# - No test for closed wallet state
# - withdraw! missing boundary case (exact balance)

RSpec.describe Wallet, type: :model do
  let(:user) { create(:user) }
  let(:wallet) { create(:wallet, user: user, balance: 1000) }

  describe '#deposit!' do
    it 'increases balance' do
      wallet.deposit!(500)
      expect(wallet.reload.balance).to eq(1500)
    end

    it 'raises on negative amount' do
      expect { wallet.deposit!(-100) }.to raise_error(ArgumentError)
    end

    it 'raises on zero amount' do
      expect { wallet.deposit!(0) }.to raise_error(ArgumentError)
    end

    context 'when wallet is suspended' do
      before { wallet.update!(status: 'suspended') }

      it 'raises error' do
        expect { wallet.deposit!(100) }.to raise_error('Wallet is not active')
      end
    end

    # Gap: no test for closed wallet
  end

  describe '#withdraw!' do
    it 'decreases balance' do
      wallet.withdraw!(500)
      expect(wallet.reload.balance).to eq(500)
    end

    it 'raises on negative amount' do
      expect { wallet.withdraw!(-100) }.to raise_error(ArgumentError)
    end

    it 'raises on insufficient balance' do
      expect { wallet.withdraw!(2000) }.to raise_error('Insufficient balance')
    end

    # Gap: no test for exact balance withdrawal (boundary)
    # Gap: no test for suspended/closed wallet
  end
end
