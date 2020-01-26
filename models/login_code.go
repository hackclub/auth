package models

import (
	"crypto/rand"
	"io"
	"log"
	"strconv"
	"time"

	"github.com/fabioberger/airtable-go"
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

	if err := db.client.CreateRecord("Login Codes", &code); err != nil {
		return nil, err
	}

	return &code, nil
}

// LoginCode is nil if not found, error is only thrown if there's a
// request error
func (db *DB) GetActiveLoginCode(u *User, code string) (*LoginCode, error) {
	const minutesValid = 15

	// TODO Properly escape the code they send
	listParams := airtable.ListParameters{
		FilterByFormula: `AND(
		  {User} = "` + strconv.Itoa(u.Fields.ID) + `",
		  DATETIME_DIFF(NOW(), {Created}, 'minutes') < ` + strconv.Itoa(minutesValid) + `,
		  {Login Code} = "` + code + `",
		  {Auth Token} = BLANK()
		)`,
	}

	codes := []LoginCode{}
	if err := db.client.ListRecords("Login Codes", &codes, listParams); err != nil {
		return nil, err
	}

	if len(codes) == 0 {
		return nil, nil
	}

	return &codes[0], nil
}
