// An echo server with gorilla/websocket, for comparison with the Idris
// one: `goserver PORT`; prints "listening", stops after GET /quit.
package main

import (
	"fmt"
	"net/http"
	"os"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}

func main() {
	quit := make(chan struct{})
	mux := http.NewServeMux()
	mux.HandleFunc("/quit", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "bye")
		close(quit)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		c, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer c.Close()
		for {
			t, m, err := c.ReadMessage()
			if err != nil {
				return
			}
			if c.WriteMessage(t, m) != nil {
				return
			}
		}
	})
	go http.ListenAndServe("127.0.0.1:"+os.Args[1], mux)
	fmt.Println("listening")
	<-quit
}
