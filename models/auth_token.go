package models

import (
	"time"

	"github.com/hackclub/auth/util"
)

func generateToken(length int) (string, error) {
	return util.GenerateRandomString(length)
}

type AuthToken struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		ID               int       `json:"ID,omitempty"`
		User             []string  `json:"User"`
		Created          time.Time `json:"Created"`
		Token            string    `json:"Token"`
		LoginCode        []string  `json:"Login Code"`
		CreatorIP        string    `json:"Creator IP"`
		CreatorUserAgent string    `json:"Creator User Agent"`
	} `json:"fields"`
}

func (db *DB) CreateAuthToken(userRecordID, loginCodeRecordID, ip, userAgent string) (*AuthToken, error) {
	const tokenLength = 64

	tokenStr, err := generateToken(tokenLength)
	if err != nil {
		return nil, err
	}

	token := AuthToken{}
	token.Fields.User = []string{userRecordID}
	token.Fields.Created = time.Now()
	token.Fields.Token = tokenStr
	token.Fields.LoginCode = []string{loginCodeRecordID}
	token.Fields.CreatorIP = ip
	token.Fields.CreatorUserAgent = userAgent

	if err := db.client.CreateRecord("Auth Tokens", &token); err != nil {
		return nil, err
	}

	return &token, nil
}
