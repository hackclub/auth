package main

import (
	"errors"
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

func (db *DB) CreateLoginCode(userRec, ip, userAgent, codeStr string) (*LoginCode, error) {
	code := LoginCode{}
	code.Fields.User = []string{userRec}
	code.Fields.Created = time.Now()
	code.Fields.CreatorIP = ip
	code.Fields.CreatorUserAgent = userAgent
	code.Fields.LoginCode = codeStr
	code.Fields.SentMethod = "Email"

	if err := db.client.CreateRecord("Login Codes", &code); err != nil {
		return nil, err
	}

	return &code, nil
}
