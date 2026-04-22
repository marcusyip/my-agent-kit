package main

import (
	"log"
	"net/http"

	"github.com/example/sample-app-go/internal/handler"
	"github.com/example/sample-app-go/internal/payment"
	"github.com/example/sample-app-go/internal/service"
	"github.com/example/sample-app-go/internal/store"
)

func main() {
	repo := store.NewMemoryRepo()
	gateway := payment.NewStubGateway()
	txService := service.NewTransactionService(repo, gateway)

	txHandler := handler.NewTransactionsHandler(repo, txService)
	walletHandler := handler.NewWalletsHandler(repo)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/transactions", txHandler.Index)
	mux.HandleFunc("POST /api/v1/transactions", txHandler.Create)
	mux.HandleFunc("GET /api/v1/transactions/{id}", txHandler.Show)
	mux.HandleFunc("GET /api/v1/wallets", walletHandler.Index)
	mux.HandleFunc("POST /api/v1/wallets", walletHandler.Create)
	mux.HandleFunc("PATCH /api/v1/wallets/{id}", walletHandler.Update)

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
