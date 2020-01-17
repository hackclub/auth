package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"runtime/debug"
	"strconv"
	"strings"

	"github.com/badoux/checkmail"
	"github.com/go-gomail/gomail"
	"github.com/joho/godotenv"
)

var db *DB
var mailer *Mailer

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Fatal("error loading .env file")
	}

	// airtable init

	airtableAPIKey := os.Getenv("AIRTABLE_API_KEY")
	airtableBase := os.Getenv("AIRTABLE_BASE")

	db, err = NewDB(airtableAPIKey, airtableBase)
	if err != nil {
		log.Fatal("error initializing db:", err)
	}

	// mailer init

	host := os.Getenv("SMTP_HOST")
	port, err := strconv.Atoi(os.Getenv("SMTP_PORT"))
	if err != nil {
		log.Fatal(err)
	}
	username, password := os.Getenv("SMTP_USERNAME"), os.Getenv("SMTP_PASSWORD")

	mailer = NewMailer(host, port, username, password)
	go mailer.StartDaemon()
	defer mailer.StopDaemon()

	// http server init

	http.HandleFunc("/login_codes", createLoginCodeHandler) // POST

	log.Println("Server listening on 8080...")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func respError(w http.ResponseWriter, statusCode int, msg string) {
	// {
	//   "error": "<msg>"
	// }
	data := map[string]string{
		"error": msg,
	}

	resp(w, statusCode, data)
}

func respFieldError(w http.ResponseWriter, field, msg string) {
	// Copies Rails error format.
	//
	// Example where field = "email" and msg = "is not an email":
	//
	// {
	//   "errors": {
	//     "email": [
	//       "is not an email"
	//     ]
	//   }
	// }
	//
	data := map[string]interface{}{
		"errors": map[string]interface{}{
			field: []interface{}{msg},
		},
	}

	resp(w, http.StatusUnprocessableEntity, data)
}

func resp(w http.ResponseWriter, code int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")

	w.WriteHeader(code)

	enc := json.NewEncoder(w)
	if err := enc.Encode(data); err != nil {
		log.Fatal(err)
	}
}

// handlePanic intercepts a panic, logs the error, and displays a nice - if
// ambiguous - error to the user. panics should only be used for unexpected
// internal errors, like a 500 from airtable's api
func handlePanic(w http.ResponseWriter) {
	if r := recover(); r != nil {
		log.Println("recovered panic:", r)
		debug.PrintStack()
		respError(w, http.StatusInternalServerError, "unexpected internal error, see logs")
	}
}

func ip(r *http.Request) string {
	fwdedIp := r.Header.Get("X-Forwarded-For")
	if fwdedIp != "" {
		return fwdedIp
	}

	return r.RemoteAddr
}

type loginCodeReq struct {
	Email string `json:"email"`
}

type loginCodeResp struct {
	ID     int    `json:"id"`
	Email  string `json:"email"`
	Status string `json:"status"`
}

func createLoginCodeHandler(w http.ResponseWriter, r *http.Request) {
	defer handlePanic(w)

	if r.Method != "POST" {
		respError(w, http.StatusNotFound, "not found")
		return
	}

	var req loginCodeReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respError(w, http.StatusBadRequest, "malformed request")
		return
	}

	email := req.Email

	email = strings.TrimSpace(email)
	email = strings.ToLower(email)

	if err := checkmail.ValidateFormat(email); err != nil {
		respFieldError(w, "email", "is not an email")
		return
	}

	user, err := db.GetUserByEmail(email)
	if err != nil {
		panic(err)
	}
	if user == nil {
		user, err = db.CreateUser(email, "")
		if err != nil {
			panic(err)
		}
	}

	code, err := db.CreateLoginCode(
		user.AirtableID,
		ip(r),
		r.Header.Get("User-Agent"),
	)
	if err != nil {
		panic(err)
	}

	// Email login code
	m := gomail.NewMessage()
	m.SetHeader("From", "Hack Club Team <team@hackclub.com>")
	m.SetHeader("To", m.FormatAddress(user.Fields.Email, ""))
	m.SetHeader("Subject", "Hack Club Login Code: "+code.Pretty())
	m.SetBody("text/plain", `Hi 👋,

You requested a login code for Hack Club (https://hackclub.com). It's here:

    `+code.Pretty()+`

It will expire in 15 minutes.

- Hack Club
`)
	m.AddAlternative("text/html", `
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  </head>
  <body>
    <p>Hi 👋,</p>
    <p>You requested a login code for <a href="https://hackclub.com">Hack Club</a>. It's here:</p>

    <pre style="text-align: center; background-color: #ebebeb; padding: 8px 0; font-size: 1.5em; border-radius: 4px"><b>`+code.Pretty()+`</b></pre>
    <p>It will expire in 15 minutes.</p>
    <p>Tip: you can triple-click the box to copy-paste the whole thing, including the dash in the middle.</p>
    <p>- Hack Club</p>
  </body>
</html>
	`)

	mailer.Messages <- m

	resp(w, http.StatusOK,
		loginCodeResp{
			ID:     user.Fields.ID,
			Email:  user.Fields.Email,
			Status: "login code sent",
		})
}
