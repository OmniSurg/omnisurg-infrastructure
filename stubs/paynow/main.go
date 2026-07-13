// paynow-stub returns a deterministic fake payment-initiation response
// and a deterministic webhook payload on demand.
package main

import (
	"encoding/json"
	"log"
	"net/http"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("/initiatetransaction", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-www-form-urlencoded")
		_, _ = w.Write([]byte("status=Ok&pollurl=http://paynow-stub:9002/poll/stub-001&hash=stub"))
	})
	mux.HandleFunc("/poll/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-www-form-urlencoded")
		_, _ = w.Write([]byte("status=Paid&reference=stub-001&amount=10.00&hash=stub"))
	})
	mux.HandleFunc("/webhook", func(w http.ResponseWriter, r *http.Request) {
		payload := map[string]any{
			"status":    "Paid",
			"reference": "stub-001",
			"amount":    "10.00",
			"hash":      "stub",
		}
		_ = json.NewEncoder(w).Encode(payload)
	})
	log.Println("paynow-stub on :9002")
	log.Fatal(http.ListenAndServe(":9002", mux))
}
