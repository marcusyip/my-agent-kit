# frozen_string_literal: true

RSpec.describe TransactionService do
  let(:user) { create(:user) }
  let(:wallet) { create(:wallet, user: user, currency: 'USD', status: 'active') }

  describe '#call' do
    let(:params) { { amount: 100, currency: 'USD', description: 'Test' } }
    let(:service) { described_class.new(user: user, wallet: wallet, params: params) }

    context 'with valid params' do
      it 'calls build_transaction' do
        expect(service).to receive(:build_transaction).and_call_original
        service.call
      end

      it 'calls validate_wallet_active!' do
        expect(service).to receive(:validate_wallet_active!).and_call_original
        service.call
      end

      it 'calls validate_currency_match!' do
        expect(service).to receive(:validate_currency_match!).and_call_original
        service.call
      end

      it 'returns a successful result' do
        result = service.call
        expect(result.success?).to be true
        expect(result.transaction).to be_persisted
      end
    end

    context 'when wallet is inactive' do
      before { wallet.update!(status: 'suspended') }

      it 'returns failure result' do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to eq('Wallet is not active')
      end
    end

    context 'when category is payment' do
      let(:params) { { amount: 100, currency: 'USD', category: 'payment' } }

      it 'calls charge_payment_gateway' do
        allow(PaymentGateway).to receive(:charge).and_return(double(success?: true))
        expect(service).to receive(:charge_payment_gateway).and_call_original
        service.call
      end
    end
  end
end
