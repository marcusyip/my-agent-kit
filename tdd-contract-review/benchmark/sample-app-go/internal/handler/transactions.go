package handler

import (
	"encoding/json"
	"math/big"
	"net/http"
	"strconv"
	"time"

	"github.com/example/sample-app-go/internal/model"
	"github.com/example/sample-app-go/internal/service"
	"github.com/example/sample-app-go/internal/store"
)

type TransactionsHandler struct {
	repo    *store.MemoryRepo
	service *service.TransactionService
}

func NewTransactionsHandler(repo *store.MemoryRepo, svc *service.TransactionService) *TransactionsHandler {
	return &TransactionsHandler{repo: repo, service: svc}
}

type createTxPayload struct {
	Transaction struct {
		WalletID    int64  `json:"wallet_id"`
		Amount      string `json:"amount"`
		Currency    string `json:"currency"`
		Description string `json:"description"`
		Category    string `json:"category"`
	} `json:"transaction"`
}

func (h *TransactionsHandler) Index(w http.ResponseWriter, r *http.Request) {
	user, err := authenticateUser(r, h.repo)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
		return
	}

	q := r.URL.Query()
	filter := store.TransactionFilter{UserID: user.ID, Status: q.Get("status")}
	if v := q.Get("start_date"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			filter.StartDate = &t
		}
	}
	if v := q.Get("end_date"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			end := t.Add(24*time.Hour - time.Nanosecond)
			filter.EndDate = &end
		}
	}
	filter.Page, _ = strconv.Atoi(q.Get("page"))
	filter.PerPage, _ = strconv.Atoi(q.Get("per_page"))

	result := h.repo.ListTransactions(filter)
	items := make([]map[string]any, 0, len(result.Transactions))
	for _, t := range result.Transactions {
		items = append(items, serializeTransaction(t))
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"transactions": items,
		"meta": map[string]any{
			"total":    result.Total,
			"page":     result.Page,
			"per_page": result.PerPage,
		},
	})
}

func (h *TransactionsHandler) Create(w http.ResponseWriter, r *http.Request) {
	user, err := authenticateUser(r, h.repo)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
		return
	}

	var payload createTxPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid JSON"})
		return
	}

	wallet, err := h.repo.FindWalletForUser(user.ID, payload.Transaction.WalletID)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"error": "Wallet not found"})
		return
	}

	amount, ok := new(big.Float).SetString(payload.Transaction.Amount)
	if !ok {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"error": "invalid amount"})
		return
	}

	result := h.service.Call(user, wallet, service.CreateParams{
		Amount:      amount,
		Currency:    payload.Transaction.Currency,
		Description: payload.Transaction.Description,
		Category:    model.TransactionCategory(payload.Transaction.Category),
	})

	if !result.Success {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{
			"error":   result.Error,
			"details": result.Details,
		})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"transaction": serializeTransaction(result.Transaction),
	})
}

func (h *TransactionsHandler) Show(w http.ResponseWriter, r *http.Request) {
	user, err := authenticateUser(r, h.repo)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
		return
	}

	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "Transaction not found"})
		return
	}

	tx, err := h.repo.FindTransactionForUser(user.ID, id)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "Transaction not found"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"transaction": serializeTransaction(tx)})
}

func serializeTransaction(t *model.Transaction) map[string]any {
	return map[string]any{
		"id":          t.ID,
		"amount":      t.Amount.Text('f', 8),
		"currency":    t.Currency,
		"status":      string(t.Status),
		"description": t.Description,
		"category":    string(t.Category),
		"wallet_id":   t.WalletID,
		"created_at":  t.CreatedAt.Format(time.RFC3339),
		"updated_at":  t.UpdatedAt.Format(time.RFC3339),
	}
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
