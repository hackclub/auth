package main

import (
	"log"
	"time"

	"github.com/go-gomail/gomail"
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
