CREATE TABLE transactions (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NOT NULL REFERENCES users(id),
  wallet_id   BIGINT NOT NULL REFERENCES wallets(id),
  amount      NUMERIC(20, 8) NOT NULL,
  currency    VARCHAR NOT NULL,
  status      VARCHAR NOT NULL DEFAULT 'pending',
  description VARCHAR,
  category    VARCHAR NOT NULL DEFAULT 'transfer',
  created_at  TIMESTAMP NOT NULL,
  updated_at  TIMESTAMP NOT NULL
);

CREATE INDEX index_transactions_on_user_id_and_created_at ON transactions (user_id, created_at);
CREATE INDEX index_transactions_on_status ON transactions (status);
CREATE INDEX index_transactions_on_user_id ON transactions (user_id);
CREATE INDEX index_transactions_on_wallet_id ON transactions (wallet_id);
