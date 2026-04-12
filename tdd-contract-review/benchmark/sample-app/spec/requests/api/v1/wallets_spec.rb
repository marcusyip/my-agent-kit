# frozen_string_literal: true

# Intentional gaps for benchmark:
# - No tests at all for PATCH /wallets/:id
# - Index test is minimal
# - Missing: duplicate currency scenario
# - Missing: status field scenarios (suspended, closed)
# - PATCH error response leaks wallet balance and user_id (data leak bug)

RSpec.describe 'Api::V1::Wallets', type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  describe 'POST /api/v1/wallets' do
    let(:params) do
      {
        wallet: {
          currency: currency,
          name: name
        }
      }
    end
    let(:currency) { 'USD' }
    let(:name) { 'My USD Wallet' }

    context 'with valid params' do
      it 'creates a wallet' do
        expect {
          post '/api/v1/wallets', params: params, headers: headers
        }.to change(Wallet, :count).by(1)

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['wallet']['currency']).to eq('USD')
        expect(body['wallet']['name']).to eq('My USD Wallet')
        expect(body['wallet']['balance']).to eq('0.0')
        expect(body['wallet']['status']).to eq('active')
      end
    end

    context 'when currency is nil' do
      let(:currency) { nil }

      it 'returns 422' do
        post '/api/v1/wallets', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when currency is invalid' do
      let(:currency) { 'XYZ' }

      it 'returns 422' do
        post '/api/v1/wallets', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'returns 422' do
        post '/api/v1/wallets', params: params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    # Gap: no test for duplicate currency per user
    # Gap: no test for name too long (> 100 chars)
  end

  describe 'GET /api/v1/wallets' do
    it 'returns wallets' do
      create_list(:wallet, 2, user: user)
      get '/api/v1/wallets', headers: headers
      expect(response).to have_http_status(:ok)
      # Gap: doesn't verify response shape or ordering
    end
  end

  # Gap: no tests for PATCH /api/v1/wallets/:id at all
end
