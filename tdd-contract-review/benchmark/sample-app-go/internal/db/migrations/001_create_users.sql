CREATE TABLE users (
  id                 BIGSERIAL PRIMARY KEY,
  email              VARCHAR NOT NULL,
  name               VARCHAR NOT NULL,
  encrypted_password VARCHAR NOT NULL,
  created_at         TIMESTAMP NOT NULL,
  updated_at         TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX index_users_on_email ON users (email);
