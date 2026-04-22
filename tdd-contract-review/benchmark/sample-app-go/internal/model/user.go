package model

import (
	"errors"
	"regexp"
	"strings"
	"time"
)

var emailRegex = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`)

type User struct {
	ID                int64
	Email             string
	Name              string
	EncryptedPassword string
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

func (u *User) Validate() error {
	if strings.TrimSpace(u.Email) == "" {
		return errors.New("email is required")
	}
	if !emailRegex.MatchString(u.Email) {
		return errors.New("email format is invalid")
	}
	if strings.TrimSpace(u.Name) == "" {
		return errors.New("name is required")
	}
	if len(u.Name) > 255 {
		return errors.New("name too long (max 255)")
	}
	return nil
}
