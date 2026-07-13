// zimrate-stub returns a fixture USD to ZWG rate so the currency service can
// be developed without contacting the real ZimRate API.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("/api/v1/rates", func(w http.ResponseWriter, r *http.Request) {
		payload := map[string]any{
			"pair":   "USD/ZWG",
			"rate":   26.7692,
			"as_of":  time.Now().UTC().Format(time.RFC3339),
			"source": "stub",
			"basis":  "fixture",
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(payload)
	})
	log.Println("zimrate-stub on :9003")
	log.Fatal(http.ListenAndServe(":9003", mux))
}
