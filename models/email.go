package models

import "github.com/go-gomail/gomail"

type Email struct {
	AirtableID string `json:"id,omitempty"`
	Fields     struct {
		ID        int      `json:"ID,omitempty"`
		User      []string `json:"User"`
		LoginCode []string `json:"Login Code"`
		To        string   `json:"To Email"`
		From      string   `json:"From Email"`
		Subject   string   `json:"Subject"`
		PlainText string   `json:"Plain Text Body"`
		HTML      string   `json:"HTML Body"`
	} `json:"fields"`
}

func (e Email) Message() *gomail.Message {
	m := gomail.NewMessage()
	m.SetHeader("From", e.Fields.From)
	m.SetHeader("To", e.Fields.To)
	m.SetHeader("Subject", e.Fields.Subject)
	m.SetBody("text/plain", e.Fields.PlainText)
	m.AddAlternative("text/html", e.Fields.HTML)
	return m
}

// note: modifies email fields with what airtable gives us
func (db DB) CreateEmail(email *Email) error {
	return db.client.CreateRecord("Sent Emails", &email)
}

func NewEmailLoginCode(user *User, code *LoginCode) Email {
	from := "Hack Club Team <team@hackclub.com>"
	to := user.Fields.Email
	subject := "Hack Club Login Code: " + code.Pretty()
	plainText := `Hi 👋,

You requested a login code for Hack Club (https://hackclub.com). It's here:

    ` + code.Pretty() + `

It will expire in 15 minutes.

- Hack Club
`
	html := `
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  </head>
  <body>
    <p>Hi 👋,</p>
    <p>You requested a login code for <a href="https://hackclub.com">Hack Club</a>. It's here:</p>

    <pre style="text-align: center; background-color: #ebebeb; padding: 8px 0; font-size: 1.5em; border-radius: 4px"><b>` + code.Pretty() + `</b></pre>
    <p>It will expire in 15 minutes.</p>
    <p>Tip: you can triple-click the box to copy-paste the whole thing, including the dash in the middle.</p>
    <p>- Hack Club</p>
  </body>
</html>`

	email := Email{}
	email.Fields.User = []string{user.AirtableID}
	email.Fields.LoginCode = []string{code.AirtableID}
	email.Fields.To = to
	email.Fields.From = from
	email.Fields.Subject = subject
	email.Fields.PlainText = plainText
	email.Fields.HTML = html

	return email
}
