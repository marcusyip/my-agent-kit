package model

import (
	"errors"
	"math/big"
	"time"
)

type TransactionStatus string

const (
	TxPending   TransactionStatus = "pending"
	TxCompleted TransactionStatus = "completed"
	TxFailed    TransactionStatus = "failed"
	TxReversed  TransactionStatus = "reversed"
)

type TransactionCategory string

const (
	CategoryTransfer   TransactionCategory = "transfer"
	CategoryPayment    TransactionCategory = "payment"
	CategoryDeposit    TransactionCategory = "deposit"
	CategoryWithdrawal TransactionCategory = "withdrawal"
)

type Transaction struct {
	ID          int64
	UserID      int64
	WalletID    int64
	Amount      *big.Float
	Currency    string
	Status      TransactionStatus
	Description string
	Category    TransactionCategory
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

var maxTransactionAmount = big.NewFloat(1_000_000)

func (t *Transaction) Validate() error {
	if t.Amount == nil {
		return errors.New("amount is required")
	}
	if t.Amount.Sign() <= 0 {
		return errors.New("amount must be greater than zero")
	}
	if t.Amount.Cmp(maxTransactionAmount) > 0 {
		return errors.New("amount exceeds maximum (1,000,000)")
	}
	if _, ok := allowedCurrencies[t.Currency]; !ok {
		return errors.New("currency must be one of USD, EUR, GBP, BTC, ETH")
	}
	if t.Status == "" {
		return errors.New("status is required")
	}
	if len(t.Description) > 500 {
		return errors.New("description too long (max 500)")
	}
	return nil
}

func (t *Transaction) IsPayment() bool {
	return t.Category == CategoryPayment
}

func (t *Transaction) IsDeposit() bool {
	return t.Category == CategoryDeposit
}
