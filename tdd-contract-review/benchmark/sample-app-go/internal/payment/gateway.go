package payment

import (
	"errors"
	"math/big"
)

type ChargeRequest struct {
	Amount        *big.Float
	Currency      string
	UserID        int64
	TransactionID int64
}

type ChargeResponse struct {
	Success       bool
	ProviderRef   string
	FailureReason string
}

type Gateway interface {
	Charge(req ChargeRequest) (ChargeResponse, error)
}

type StubGateway struct{}

func NewStubGateway() *StubGateway {
	return &StubGateway{}
}

func (g *StubGateway) Charge(req ChargeRequest) (ChargeResponse, error) {
	if req.Amount == nil || req.Amount.Sign() <= 0 {
		return ChargeResponse{}, errors.New("invalid charge amount")
	}
	return ChargeResponse{
		Success:     true,
		ProviderRef: "stub-ok",
	}, nil
}

var ErrChargeDeclined = errors.New("charge declined by gateway")
