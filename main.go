package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"github.com/badoux/checkmail"
	"github.com/fabioberger/airtable-go"
	"github.com/go-gomail/gomail"
	"github.com/joho/godotenv"
)

type Mailer struct {
	Messages chan *gomail.Message
	Host     string
	Port     int
	Username string
	Password string
}

// TODO Do real error handling, really for this whole method
func (m *Mailer) StartDaemon() {
	log.Println("starting mailer daemon")
	d := gomail.NewDialer(m.Host, m.Port, m.Username, m.Password)
	var s gomail.SendCloser
	var err error
	open := false
	for {
		select {
		case m, ok := <-m.Messages:
			log.Println("mailer processing message")
			if !ok {
				return
			}
			if !open {
				if s, err = d.Dial(); err != nil {
					panic(err)
				}
				open = true
			}
			if err := gomail.Send(s, m); err != nil {
				log.Panic(err)
			}
		case <-time.After(30 * time.Second):
			if open {
				if err := s.Close(); err != nil {
					panic(err)
				}
				open = false
			}
		}
	}
}

func (m *Mailer) StopDaemon() {
	log.Println("stopping mailer daemon")
	close(m.Messages)
}

func NewMailer(host string, port int, username, password string) *Mailer {
	return &Mailer{
		Messages: make(chan *gomail.Message),
		Host:     host,
		Port:     port,
		Username: username,
		Password: password,
	}
}

var client *airtable.Client
var mailer *Mailer

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Fatal("error loading .env file")
	}

	// airtable init

	airtableAPIKey := os.Getenv("AIRTABLE_API_KEY")
	airtableBase := os.Getenv("AIRTABLE_BASE")

	client, err = airtable.New(airtableAPIKey, airtableBase)
	if err != nil {
		log.Fatal("error loading airtable:", err)
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

type user struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		ID                  int       `json:"ID,omitempty"` // omitempty so Airtable doesn't try to set the ID to 0 when this field isn't set
		Created             time.Time `json:"Created"`
		Email               string    `json:"Email"`
		Phone               string    `json:"Phone Number"`
		PreferredAuthMethod string    `json:"Preferred Auth Method"`
	} `json:"fields"`
}

func createUser(email, phone string) (*user, error) {
	u := user{}
	u.Fields.Created = time.Now()
	u.Fields.Email = email
	u.Fields.Phone = phone
	u.Fields.PreferredAuthMethod = "Email"

	if err := client.CreateRecord("Users", &u); err != nil {
		return nil, err
	}

	return &u, nil
}

// user is nil if not found, error is only thrown if there's a request error
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

// 123456 -> 123-456
func prettyLoginCode(rawCode string) string {
	return rawCode[:3] + "-" + rawCode[3:]
}

// only validating format for now, not attempting to validate host
func validateEmail(email string) error {
	if err := checkmail.ValidateFormat(email); err != nil {
		return err
	}

	return nil
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

	if err := validateEmail(email); err != nil {
		respFieldError(w, "email", "is not an email")
		return
	}

	user, err := getUserByEmail(email)
	if err != nil {
		panic(err)
	}
	if user == nil {
		user, err = createUser(email, "")
		if err != nil {
			panic(err)
		}
	}

	code, err := createLoginCode(
		user.AirtableID,
		ip(r),
		r.Header.Get("User-Agent"),
		generateLoginCode(),
	)
	if err != nil {
		panic(err)
	}

	// Email login code
	m := gomail.NewMessage()
	m.SetHeader("From", "Hack Club Team <team@hackclub.com>")
	m.SetHeader("To", m.FormatAddress(user.Fields.Email, ""))
	m.SetHeader("Subject", "Hack Club Login Code: "+prettyLoginCode(code.Fields.LoginCode))
	m.SetBody("text/plain", `Hi 👋,

You requested a login code for Hack Club (https://hackclub.com). It's here:

    `+prettyLoginCode(code.Fields.LoginCode)+`

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

    <pre style="text-align: center; background-color: #ebebeb; padding: 8px 0; font-size: 1.5em; border-radius: 4px"><b>`+prettyLoginCode(code.Fields.LoginCode)+`</b></pre>
    <p>It will expire in 15 minutes.</p>
    <p>Tip: you can triple-click the box to copy-paste the whole thing, including the dash in the middle.</p>
    <p>- Hack Club</p>
  </body>
</html>
	`)

	mailer.Messages <- m

	data := loginCodeResp{
		ID:     user.Fields.ID,
		Email:  user.Fields.Email,
		Status: "login code sent",
	}

	resp(w, http.StatusOK, data)
}
