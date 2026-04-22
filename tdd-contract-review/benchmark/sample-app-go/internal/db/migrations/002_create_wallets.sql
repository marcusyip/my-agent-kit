CREATE TABLE wallets (
  id         BIGSERIAL PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(id),
  currency   VARCHAR NOT NULL,
  name       VARCHAR NOT NULL,
  balance    NUMERIC(20, 8) NOT NULL DEFAULT 0,
  status     VARCHAR NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX index_wallets_on_user_id_and_currency ON wallets (user_id, currency);
CREATE INDEX index_wallets_on_user_id ON wallets (user_id);
