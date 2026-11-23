// Command goserver is the net/http counterpart of the Idris benchmark
// server: GET /hello and POST /json (decode, modify, encode).  With CERT
// and KEY in the environment it serves HTTPS (HTTP/1.1, or HTTP/2 for the
// clients that ask for it with ALPN).
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

type item struct {
	ID       int      `json:"id"`
	Name     string   `json:"name"`
	Price    float64  `json:"price"`
	Quantity int      `json:"quantity"`
	Tags     []string `json:"tags"`
	Active   bool     `json:"active"`
	Owner    string   `json:"owner"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /hello", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte("Hello, World!"))
	})
	mux.HandleFunc("POST /json", func(w http.ResponseWriter, r *http.Request) {
		var it item
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&it); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		it.Quantity *= 2
		it.Active = !it.Active
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(&it)
	})
	addr := "127.0.0.1:" + os.Getenv("PORT")
	if cert, key := os.Getenv("CERT"), os.Getenv("KEY"); cert != "" {
		log.Fatal(http.ListenAndServeTLS(addr, cert, key, mux))
	}
	log.Fatal(http.ListenAndServe(addr, mux))
}
