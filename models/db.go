package models

import (
	"crypto/rand"
	"errors"
	"io"
	"log"
	"time"

	"github.com/fabioberger/airtable-go"
)

type DB struct {
	client *airtable.Client
}

func NewDB(airtableAPIKey, airtableBaseID string) (*DB, error) {
	client, err := airtable.New(airtableAPIKey, airtableBaseID)
	if err != nil {
		return nil, err
	}

	return &DB{
		client: client,
	}, nil
}

type User struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		ID                  int       `json:"ID,omitempty"` // omitempty so Airtable doesn't try to set the ID to 0 when this field isn't set
		Created             time.Time `json:"Created"`
		Email               string    `json:"Email"`
		Phone               string    `json:"Phone Number"`
		PreferredAuthMethod string    `json:"Preferred Auth Method"`
	} `json:"fields"`
}

func (db *DB) CreateUser(email, phone string) (*User, error) {
	u := User{}
	u.Fields.Created = time.Now()
	u.Fields.Email = email
	u.Fields.Phone = phone
	u.Fields.PreferredAuthMethod = "Email"

	if err := db.client.CreateRecord("Users", &u); err != nil {
		return nil, err
	}

	return &u, nil
}

// User is nil if not found, error is only thrown if there's a
// request error
func (db *DB) GetUserByEmail(email string) (*User, error) {
	listParams := airtable.ListParameters{
		// TODO Prevent string escaping problems
		FilterByFormula: "{Email} = \"" + email + "\"",
	}

	users := []User{}
	if err := db.client.ListRecords("Users", &users, listParams); err != nil {
		return nil, err
	}

	if len(users) > 1 {
		return nil, errors.New("too many users returned, non-unique emails")
	} else if len(users) == 0 {
		return nil, nil
	}

	return &users[0], nil
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

// TODO: Make sure it doesn't collide with other active codes - actually
// probably fine as long as code searching is scoped per-user to active codes
// (wonder if there's a way to keep it all in 1 API request?)
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
