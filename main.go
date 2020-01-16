package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/fabioberger/airtable-go"
	"github.com/joho/godotenv"
)

var client *airtable.Client

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Fatal("error loading .env file")
	}

	airtableAPIKey := os.Getenv("AIRTABLE_API_KEY")
	airtableBase := os.Getenv("AIRTABLE_BASE")

	client, err = airtable.New(airtableAPIKey, airtableBase)
	if err != nil {
		log.Fatal("error loading airtable:", err)
	}

	http.HandleFunc("/login_codes", createLoginCodeHandler) // POST

	log.Println("Server listening on 8080...")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func resp(w http.ResponseWriter, code int, msg string) {
	respStruct := struct {
		Msg string `json:"msg"`
	}{
		Msg: msg,
	}

	w.WriteHeader(code)

	enc := json.NewEncoder(w)
	if err := enc.Encode(respStruct); err != nil {
		log.Fatal(err)
	}
}

type loginCodeReq struct {
	Email string `json:"email"`
}

type user struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		ID int `json:"ID"`
		// TODO Use proper date type
		Created             string `json:"Created"`
		Email               string `json:"Email"`
		Phone               string `json:"Phone Number"`
		PreferredAuthMethod string `json:"Preferred Auth Method"`
	} `json:"fields"`
}

func getUserByEmail(email string) (*user, error) {
	listParams := airtable.ListParameters{
		// TODO Prevent string escaping problems
		FilterByFormula: "{Email} = \"" + email + "\"",
	}

	users := []user{}
	if err := client.ListRecords("Users", &users, listParams); err != nil {
		return nil, err
	}

	if len(users) > 1 {
		return nil, errors.New("too many users returned, non-unique emails")
	} else if len(users) == 0 {
		return nil, nil
	}

	return &users[0], nil
}

type loginCode struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		//ID               int      `json:"ID"`
		User             []string  `json:"User"`
		Created          time.Time `json:"Created"`
		CreatorIP        string    `json:"Creator IP"`
		CreatorUserAgent string    `json:"Creator User Agent"`
		LoginCode        string    `json:"Login Code"`
		SentMethod       string    `json:"Sent Method"`
		AuthToken        []string  `json:"Auth Token"`
	} `json:"fields"`
}

func createLoginCode(userRec, ip, userAgent, codeStr string) (*loginCode, error) {
	code := loginCode{}
	code.Fields.User = []string{userRec}
	code.Fields.Created = time.Now()
	code.Fields.CreatorIP = ip
	code.Fields.CreatorUserAgent = userAgent
	code.Fields.LoginCode = codeStr
	code.Fields.SentMethod = "Email"

	if err := client.CreateRecord("Login Codes", &code); err != nil {
		return nil, err
	}

	return &code, nil
}

func ip(r *http.Request) string {
	fwdedIp := r.Header.Get("X-Forwarded-For")
	if fwdedIp != "" {
		return fwdedIp
	}

	return r.RemoteAddr
}

// TODO: Make sure it doesn't collide with other active codes
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

func createLoginCodeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		resp(w, http.StatusNotFound, "not found")
		return
	}

	var req loginCodeReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Fatal(err)
	}

	user, err := getUserByEmail(req.Email)
	if err != nil {
		log.Fatal(err)
	}

	if user == nil {
		// TODO: Handle user creation
		log.Fatal("user creation not implemented")
	}

	code, err := createLoginCode(
		user.AirtableID,
		ip(r),
		r.Header.Get("User-Agent"),
		generateLoginCode(),
	)
	if err != nil {
		log.Fatal("error creating login code:", err)
	}

	// Email login code
}
