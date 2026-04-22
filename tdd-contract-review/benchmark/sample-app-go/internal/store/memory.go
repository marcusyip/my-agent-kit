package store

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/example/sample-app-go/internal/model"
)

var ErrNotFound = errors.New("not found")

type MemoryRepo struct {
	mu           sync.RWMutex
	users        map[int64]*model.User
	wallets      map[int64]*model.Wallet
	transactions map[int64]*model.Transaction
	nextUserID   int64
	nextWalletID int64
	nextTxID     int64
}

func NewMemoryRepo() *MemoryRepo {
	return &MemoryRepo{
		users:        map[int64]*model.User{},
		wallets:      map[int64]*model.Wallet{},
		transactions: map[int64]*model.Transaction{},
	}
}

func (r *MemoryRepo) CreateUser(u *model.User) (*model.User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if err := u.Validate(); err != nil {
		return nil, err
	}
	for _, existing := range r.users {
		if existing.Email == u.Email {
			return nil, errors.New("email already taken")
		}
	}
	r.nextUserID++
	u.ID = r.nextUserID
	now := time.Now().UTC()
	u.CreatedAt, u.UpdatedAt = now, now
	r.users[u.ID] = u
	return u, nil
}

func (r *MemoryRepo) FindUser(id int64) (*model.User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	u, ok := r.users[id]
	if !ok {
		return nil, ErrNotFound
	}
	return u, nil
}

func (r *MemoryRepo) CreateWallet(w *model.Wallet) (*model.Wallet, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if err := w.Validate(); err != nil {
		return nil, err
	}
	for _, existing := range r.wallets {
		if existing.UserID == w.UserID && existing.Currency == w.Currency {
			return nil, errors.New("wallet already exists for this currency")
		}
	}
	r.nextWalletID++
	w.ID = r.nextWalletID
	now := time.Now().UTC()
	w.CreatedAt, w.UpdatedAt = now, now
	r.wallets[w.ID] = w
	return w, nil
}

func (r *MemoryRepo) FindWallet(id int64) (*model.Wallet, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	w, ok := r.wallets[id]
	if !ok {
		return nil, ErrNotFound
	}
	return w, nil
}

func (r *MemoryRepo) FindWalletForUser(userID, walletID int64) (*model.Wallet, error) {
	w, err := r.FindWallet(walletID)
	if err != nil {
		return nil, err
	}
	if w.UserID != userID {
		return nil, ErrNotFound
	}
	return w, nil
}

func (r *MemoryRepo) ListWalletsByUser(userID int64) []*model.Wallet {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := []*model.Wallet{}
	for _, w := range r.wallets {
		if w.UserID == userID {
			out = append(out, w)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Currency < out[j].Currency })
	return out
}

func (r *MemoryRepo) UpdateWallet(w *model.Wallet) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.wallets[w.ID]; !ok {
		return ErrNotFound
	}
	if err := w.Validate(); err != nil {
		return err
	}
	w.UpdatedAt = time.Now().UTC()
	r.wallets[w.ID] = w
	return nil
}

func (r *MemoryRepo) CreateTransaction(t *model.Transaction) (*model.Transaction, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if err := t.Validate(); err != nil {
		return nil, err
	}
	r.nextTxID++
	t.ID = r.nextTxID
	now := time.Now().UTC()
	t.CreatedAt, t.UpdatedAt = now, now
	r.transactions[t.ID] = t
	return t, nil
}

func (r *MemoryRepo) UpdateTransactionStatus(id int64, status model.TransactionStatus) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	t, ok := r.transactions[id]
	if !ok {
		return ErrNotFound
	}
	t.Status = status
	t.UpdatedAt = time.Now().UTC()
	return nil
}

func (r *MemoryRepo) FindTransactionForUser(userID, txID int64) (*model.Transaction, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	t, ok := r.transactions[txID]
	if !ok || t.UserID != userID {
		return nil, ErrNotFound
	}
	return t, nil
}

type TransactionFilter struct {
	UserID    int64
	StartDate *time.Time
	EndDate   *time.Time
	Status    string
	Page      int
	PerPage   int
}

type PageResult struct {
	Transactions []*model.Transaction
	Total        int
	Page         int
	PerPage      int
}

func (r *MemoryRepo) ListTransactions(f TransactionFilter) PageResult {
	r.mu.RLock()
	defer r.mu.RUnlock()
	all := []*model.Transaction{}
	for _, t := range r.transactions {
		if t.UserID != f.UserID {
			continue
		}
		if f.StartDate != nil && t.CreatedAt.Before(*f.StartDate) {
			continue
		}
		if f.EndDate != nil && t.CreatedAt.After(*f.EndDate) {
			continue
		}
		if f.Status != "" && string(t.Status) != f.Status {
			continue
		}
		all = append(all, t)
	}
	sort.Slice(all, func(i, j int) bool { return all[i].CreatedAt.After(all[j].CreatedAt) })

	page := f.Page
	if page < 1 {
		page = 1
	}
	perPage := f.PerPage
	if perPage < 1 {
		perPage = 25
	}
	start := (page - 1) * perPage
	if start > len(all) {
		start = len(all)
	}
	end := start + perPage
	if end > len(all) {
		end = len(all)
	}
	return PageResult{
		Transactions: all[start:end],
		Total:        len(all),
		Page:         page,
		PerPage:      perPage,
	}
}
