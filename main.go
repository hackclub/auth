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
	"github.com/joho/godotenv"

	"github.com/hackclub/auth/mailer"
	"github.com/hackclub/auth/models"
)

var db *models.DB
var mail *mailer.Mailer

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Fatal("error loading .env file")
	}

	// airtable init

	airtableAPIKey := os.Getenv("AIRTABLE_API_KEY")
	airtableBase := os.Getenv("AIRTABLE_BASE")

	db, err = models.NewDB(airtableAPIKey, airtableBase)
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

	mail = mailer.NewMailer(host, port, username, password)
	go mail.StartDaemon()
	defer mail.StopDaemon()

	// http server init

	http.HandleFunc("/login_codes", createLoginCodeHandler) // POST
	http.HandleFunc("/auth_tokens", createAuthTokenHandler) // POST

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
		user, err = db.CreateUser(email)
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

	// send login code email
	toSend := models.NewEmailLoginCode(user, code)

	mail.Messages <- toSend.Message()

	if err := db.CreateEmail(&toSend); err != nil {
		panic(err)
	}

	resp(w, http.StatusOK,
		loginCodeResp{
			ID:     user.Fields.ID,
			Email:  user.Fields.Email,
			Status: "login code sent",
		})
}

type authTokenReq struct {
	UserID    int    `json:"user_id"`
	LoginCode string `json:"login_code"`
}

type authTokenResp struct {
	AuthToken string `json:"auth_token"`
}

func createAuthTokenHandler(w http.ResponseWriter, r *http.Request) {
	defer handlePanic(w)

	if r.Method != "POST" {
		respError(w, http.StatusNotFound, "not found")
		return
	}

	var req authTokenReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respError(w, http.StatusBadRequest, "malformed request")
		return
	}

	user, err := db.GetUserByID(req.UserID)
	if err != nil {
		panic(err)
	}
	if user == nil {
		respFieldError(w, "user", "not found")
		return
	}

	code, err := db.GetActiveLoginCode(user, req.LoginCode)
	if err != nil {
		panic(err)
	}
	if code == nil {
		respFieldError(w, "login_code", "invalid")
		return
	}

	token, err := db.CreateAuthToken(
		user.AirtableID,
		code.AirtableID,
		ip(r),
		r.Header.Get("User-Agent"),
	)
	if err != nil {
		panic(err)
	}

	resp(w, http.StatusOK,
		authTokenResp{
			AuthToken: token.Fields.Token,
		})
}
