package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/example/sample-app-go/internal/model"
	"github.com/example/sample-app-go/internal/store"
)

type WalletsHandler struct {
	repo *store.MemoryRepo
}

func NewWalletsHandler(repo *store.MemoryRepo) *WalletsHandler {
	return &WalletsHandler{repo: repo}
}

type walletPayload struct {
	Wallet struct {
		Currency string `json:"currency"`
		Name     string `json:"name"`
		Status   string `json:"status"`
	} `json:"wallet"`
}

func (h *WalletsHandler) Index(w http.ResponseWriter, r *http.Request) {
	user, err := authenticateUser(r, h.repo)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
		return
	}
	wallets := h.repo.ListWalletsByUser(user.ID)
	out := make([]map[string]any, 0, len(wallets))
	for _, item := range wallets {
		out = append(out, serializeWallet(item))
	}
	writeJSON(w, http.StatusOK, map[string]any{"wallets": out})
}

func (h *WalletsHandler) Create(w http.ResponseWriter, r *http.Request) {
	user, err := authenticateUser(r, h.repo)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
		return
	}

	var payload walletPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid JSON"})
		return
	}

	status := model.WalletStatus(payload.Wallet.Status)
	if status == "" {
		status = model.WalletActive
	}
	wallet := &model.Wallet{
		UserID:   user.ID,
		Currency: payload.Wallet.Currency,
		Name:     payload.Wallet.Name,
		Status:   status,
	}

	created, err := h.repo.CreateWallet(wallet)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"wallet": serializeWallet(created)})
}

func (h *WalletsHandler) Update(w http.ResponseWriter, r *http.Request) {
	user, err := authenticateUser(r, h.repo)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
		return
	}

	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "Wallet not found"})
		return
	}

	wallet, err := h.repo.FindWalletForUser(user.ID, id)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "Wallet not found"})
		return
	}

	var payload walletPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid JSON"})
		return
	}

	if payload.Wallet.Currency != "" {
		wallet.Currency = payload.Wallet.Currency
	}
	if payload.Wallet.Name != "" {
		wallet.Name = payload.Wallet.Name
	}
	if payload.Wallet.Status != "" {
		wallet.Status = model.WalletStatus(payload.Wallet.Status)
	}

	if err := h.repo.UpdateWallet(wallet); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]any{"error": "Wallet not found"})
			return
		}
		// BUG (seeded): leaks internal state — balance, user_id, full error chain in 422 response.
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{
			"error":     err.Error(),
			"wallet_id": wallet.ID,
			"balance":   wallet.Balance.Text('f', 8),
			"user_id":   wallet.UserID,
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"wallet": serializeWallet(wallet)})
}

func serializeWallet(w *model.Wallet) map[string]any {
	return map[string]any{
		"id":         w.ID,
		"currency":   w.Currency,
		"name":       w.Name,
		"balance":    w.Balance.Text('f', 8),
		"status":     string(w.Status),
		"created_at": w.CreatedAt.Format(time.RFC3339),
	}
}
