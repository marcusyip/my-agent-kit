# frozen_string_literal: true

# Intentional gaps for benchmark:
# - Happy path only checks status code, not response body fields
# - No DB state assertions in happy path
# - Missing: description field scenarios
# - Missing: category field scenarios
# - Missing: payment gateway external API scenarios
# - currency field tested but missing empty string edge case
# - No pagination tests for index
# - No insufficient balance test (amount > wallet balance → 422)
# - No exact balance test (amount == balance → success, balance becomes zero)
# - No start_date/end_date filter tests on index
# - Error response leaks wallet balance in InsufficientBalanceError details

RSpec.describe 'Api::V1::Transactions', type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:wallet) { create(:wallet, user: user, currency: 'USD') }

  describe 'POST /api/v1/transactions' do
    let(:params) do
      {
        transaction: {
          amount: amount,
          currency: currency,
          wallet_id: wallet.id
        }
      }
    end
    let(:amount) { '100.50' }
    let(:currency) { 'USD' }

    # Gap: happy path only checks status, not response body or DB
    context 'with valid params' do
      it 'returns 201' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:created)
      end
    end

    context 'when amount is nil' do
      let(:amount) { nil }

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when amount is negative' do
      let(:amount) { '-10' }

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when currency is nil' do
      let(:currency) { nil }

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when currency is invalid' do
      let(:currency) { 'INVALID' }

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when wallet does not exist' do
      let(:params) do
        {
          transaction: {
            amount: amount,
            currency: currency,
            wallet_id: 999_999
          }
        }
      end

      it 'returns 422' do
        post '/api/v1/transactions', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    # Gap: no test for wallet belonging to another user
    # Gap: no test for suspended/closed wallet
    # Gap: no test for currency mismatch with wallet
  end

  describe 'GET /api/v1/transactions/:id' do
    let(:transaction) { create(:transaction, user: user, wallet: wallet) }

    it 'returns the transaction' do
      get "/api/v1/transactions/#{transaction.id}", headers: headers
      expect(response).to have_http_status(:ok)
      # Gap: doesn't verify response body shape
    end

    context 'when transaction does not exist' do
      it 'returns 404' do
        get '/api/v1/transactions/999999', headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    # Gap: no test for transaction belonging to another user
  end

  describe 'GET /api/v1/transactions' do
    it 'returns transactions' do
      create_list(:transaction, 3, user: user, wallet: wallet)
      get '/api/v1/transactions', headers: headers
      expect(response).to have_http_status(:ok)
      # Gap: doesn't verify response shape, pagination meta, or ordering
    end
  end
end
