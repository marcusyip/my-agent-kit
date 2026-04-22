package service

import (
	"errors"
	"fmt"
	"math/big"

	"github.com/example/sample-app-go/internal/model"
	"github.com/example/sample-app-go/internal/payment"
	"github.com/example/sample-app-go/internal/store"
)

type CreateParams struct {
	Amount      *big.Float
	Currency    string
	Description string
	Category    model.TransactionCategory
}

type Result struct {
	Success     bool
	Transaction *model.Transaction
	Error       string
	Details     []string
}

type TransactionService struct {
	repo    *store.MemoryRepo
	gateway payment.Gateway
}

func NewTransactionService(repo *store.MemoryRepo, gateway payment.Gateway) *TransactionService {
	return &TransactionService{repo: repo, gateway: gateway}
}

var (
	ErrWalletInactive     = errors.New("wallet is not active")
	ErrCurrencyMismatch   = errors.New("currency does not match wallet")
	ErrInsufficientFunds  = errors.New("insufficient balance")
	ErrPaymentProcessing  = errors.New("payment processing failed")
)

func (s *TransactionService) Call(user *model.User, wallet *model.Wallet, p CreateParams) Result {
	if err := s.validateWalletActive(wallet); err != nil {
		return failure(err.Error(), []string{"Wallet must be active"})
	}
	if err := s.validateCurrencyMatch(wallet, p); err != nil {
		return failure(err.Error(), []string{"Currency must match wallet currency"})
	}
	if err := s.validateSufficientBalance(wallet, p); err != nil {
		return failure(err.Error(), []string{
			fmt.Sprintf("Current balance: %s, requested: %s", wallet.Balance.Text('f', 8), p.Amount.Text('f', 8)),
		})
	}

	tx := s.buildTransaction(user, wallet, p)
	created, err := s.repo.CreateTransaction(tx)
	if err != nil {
		return failure("Validation failed", []string{err.Error()})
	}

	if err := s.deductBalance(wallet, created); err != nil {
		return failure(err.Error(), []string{err.Error()})
	}

	if created.IsPayment() {
		s.chargePaymentGateway(user, created)
	}

	return Result{Success: true, Transaction: created}
}

func (s *TransactionService) validateWalletActive(w *model.Wallet) error {
	if !w.IsActive() {
		return ErrWalletInactive
	}
	return nil
}

func (s *TransactionService) validateCurrencyMatch(w *model.Wallet, p CreateParams) error {
	if p.Currency != w.Currency {
		return ErrCurrencyMismatch
	}
	return nil
}

func (s *TransactionService) validateSufficientBalance(w *model.Wallet, p CreateParams) error {
	if p.Amount == nil {
		return errors.New("amount is required")
	}
	if w.Balance.Cmp(p.Amount) < 0 {
		return ErrInsufficientFunds
	}
	return nil
}

func (s *TransactionService) buildTransaction(u *model.User, w *model.Wallet, p CreateParams) *model.Transaction {
	cat := p.Category
	if cat == "" {
		cat = model.CategoryTransfer
	}
	return &model.Transaction{
		UserID:      u.ID,
		WalletID:    w.ID,
		Amount:      p.Amount,
		Currency:    p.Currency,
		Description: p.Description,
		Category:    cat,
		Status:      model.TxPending,
	}
}

func (s *TransactionService) deductBalance(w *model.Wallet, tx *model.Transaction) error {
	if tx.IsDeposit() {
		return nil
	}
	return w.Withdraw(tx.Amount)
}

func (s *TransactionService) chargePaymentGateway(u *model.User, tx *model.Transaction) {
	resp, err := s.gateway.Charge(payment.ChargeRequest{
		Amount:        tx.Amount,
		Currency:      tx.Currency,
		UserID:        u.ID,
		TransactionID: tx.ID,
	})
	if err != nil || !resp.Success {
		_ = s.repo.UpdateTransactionStatus(tx.ID, model.TxFailed)
		return
	}
	_ = s.repo.UpdateTransactionStatus(tx.ID, model.TxCompleted)
}

func failure(msg string, details []string) Result {
	return Result{Success: false, Error: msg, Details: details}
}
