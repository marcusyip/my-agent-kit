package handler

import (
	"net/http"
	"strconv"

	"github.com/example/sample-app-go/internal/model"
	"github.com/example/sample-app-go/internal/store"
)

func authenticateUser(r *http.Request, repo *store.MemoryRepo) (*model.User, error) {
	raw := r.Header.Get("X-User-Id")
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return nil, store.ErrNotFound
	}
	return repo.FindUser(id)
}
