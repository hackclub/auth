package models

import (
	"crypto/rand"
	"io"
	"log"
	"time"
)

// Does not guarentee uniqueness. Must use scoping in Airtable to only grab
// active login codes for the given user.
//
// From https://stackoverflow.com/a/39482484
func generateLoginCode() string {
	const max = 6

	var table = [...]byte{'1', '2', '3', '4', '5', '6', '7', '8', '9', '0'}

	b := make([]byte, max)
	n, err := io.ReadAtLeast(rand.Reader, b, max)
	if n != max {
		log.Fatal("unexpected error when generating login code:", err)
	}

	for i := 0; i < len(b); i++ {
		b[i] = table[int(b[i])%len(table)]
	}

	return string(b)
}

type LoginCode struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		ID               int       `json:"ID,omitempty"`
		User             []string  `json:"User"`
		Created          time.Time `json:"Created"`
		CreatorIP        string    `json:"Creator IP"`
		CreatorUserAgent string    `json:"Creator User Agent"`
		LoginCode        string    `json:"Login Code"`
		SentMethod       string    `json:"Sent Method"`
		AuthToken        []string  `json:"Auth Token"`
	} `json:"fields"`
}

// 123456 -> 123-456
func (l LoginCode) Pretty() string {
	rawCode := l.Fields.LoginCode
	return rawCode[:3] + "-" + rawCode[3:]
}

func (db *DB) CreateLoginCode(userRecordID, ip, userAgent string) (*LoginCode, error) {
	code := LoginCode{}
	code.Fields.User = []string{userRecordID}
	code.Fields.Created = time.Now()
	code.Fields.CreatorIP = ip
	code.Fields.CreatorUserAgent = userAgent
	code.Fields.LoginCode = generateLoginCode()
	code.Fields.SentMethod = "Email"

	if err := db.client.CreateRecord("Login Codes", &code); err != nil {
		return nil, err
	}

	return &code, nil
}
