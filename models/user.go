package models

import (
	"errors"
	"time"

	"github.com/fabioberger/airtable-go"
)

type User struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		ID      int       `json:"ID,omitempty"` // omitempty so Airtable doesn't try to set the ID to 0 when this field isn't set
		Created time.Time `json:"Created"`
		Email   string    `json:"Email"`
	} `json:"fields"`
}

func (db *DB) CreateUser(email string) (*User, error) {
	u := User{}
	u.Fields.Created = time.Now()
	u.Fields.Email = email

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
