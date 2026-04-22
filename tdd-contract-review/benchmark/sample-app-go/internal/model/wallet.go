package model

import (
	"errors"
	"math/big"
	"strings"
	"sync"
	"time"
)

type WalletStatus string

const (
	WalletActive    WalletStatus = "active"
	WalletSuspended WalletStatus = "suspended"
	WalletClosed    WalletStatus = "closed"
)

var allowedCurrencies = map[string]struct{}{
	"USD": {}, "EUR": {}, "GBP": {}, "BTC": {}, "ETH": {},
}

type Wallet struct {
	ID        int64
	UserID    int64
	Currency  string
	Name      string
	Balance   *big.Float
	Status    WalletStatus
	CreatedAt time.Time
	UpdatedAt time.Time

	mu sync.Mutex
}

func (w *Wallet) Validate() error {
	if strings.TrimSpace(w.Currency) == "" {
		return errors.New("currency is required")
	}
	if _, ok := allowedCurrencies[w.Currency]; !ok {
		return errors.New("currency must be one of USD, EUR, GBP, BTC, ETH")
	}
	if strings.TrimSpace(w.Name) == "" {
		return errors.New("name is required")
	}
	if len(w.Name) > 100 {
		return errors.New("name too long (max 100)")
	}
	if w.Balance == nil {
		w.Balance = big.NewFloat(0)
	}
	if w.Balance.Sign() < 0 {
		return errors.New("balance must be non-negative")
	}
	return nil
}

func (w *Wallet) IsActive() bool {
	return w.Status == WalletActive
}

func (w *Wallet) Deposit(amount *big.Float) error {
	if amount == nil || amount.Sign() <= 0 {
		return errors.New("amount must be positive")
	}
	if !w.IsActive() {
		return errors.New("wallet is not active")
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	w.Balance = new(big.Float).Add(w.Balance, amount)
	w.UpdatedAt = time.Now().UTC()
	return nil
}

func (w *Wallet) Withdraw(amount *big.Float) error {
	if amount == nil || amount.Sign() <= 0 {
		return errors.New("amount must be positive")
	}
	if !w.IsActive() {
		return errors.New("wallet is not active")
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.Balance.Cmp(amount) < 0 {
		return errors.New("insufficient balance")
	}
	w.Balance = new(big.Float).Sub(w.Balance, amount)
	w.UpdatedAt = time.Now().UTC()
	return nil
}
