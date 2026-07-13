// afrosoft-stub mimics the Afrosoft SMS HTTP API so OmniSurg services can be
// developed without contacting the real provider. It implements the
// sendmessage endpoint and response shape from the Afrosoft Aggregator V4 SMS
// HTTP API document: GET /client/api/sendmessage with apikey, mobiles, sms,
// senderid query parameters, returning a JSON sms-response with a status
// error-code (000 Success, 001 required) and per recipient sent-sms-details.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
)

type statusObj struct {
	ErrorCode        string `json:"error-code"`
	ErrorStatus      string `json:"error-status"`
	ErrorDescription string `json:"error-description"`
}

type sentDetail struct {
	SMSClientID string `json:"sms-client-id"`
	MessageID   string `json:"message-id"`
	MobileNo    string `json:"mobile-no"`
}

type respDetail struct {
	SuccessCount    string       `json:"success-count"`
	FailedSMSDetails []any       `json:"failed-sms-details"`
	SentSMSDetails  []sentDetail `json:"sent-sms-details"`
}

type smsResponse struct {
	Status             statusObj    `json:"status"`
	SMSResponseDetails []respDetail `json:"sms-response-details"`
}

// sendMessage handles GET /client/api/sendmessage. It validates the mandatory
// parameters (apikey, mobiles, sms) and returns a deterministic success
// response shaped like the real Afrosoft API.
func sendMessage(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	apikey := q.Get("apikey")
	mobiles := q.Get("mobiles")
	sms := q.Get("sms")
	clientID := q.Get("client-sms-ids")

	w.Header().Set("Content-Type", "application/json")

	if apikey == "" || mobiles == "" || sms == "" {
		_ = json.NewEncoder(w).Encode(smsResponse{
			Status: statusObj{ErrorCode: "001", ErrorStatus: "required",
				ErrorDescription: "apikey, mobiles and sms are mandatory"},
		})
		return
	}

	numbers := strings.Split(mobiles, ",")
	sent := make([]sentDetail, 0, len(numbers))
	for i, n := range numbers {
		sent = append(sent, sentDetail{
			SMSClientID: clientID,
			MessageID:   "stub-msg-" + strconv.Itoa(i+1),
			MobileNo:    strings.TrimSpace(n),
		})
	}

	_ = json.NewEncoder(w).Encode(smsResponse{
		Status: statusObj{ErrorCode: "000", ErrorStatus: "Success"},
		SMSResponseDetails: []respDetail{{
			SuccessCount:     strconv.Itoa(len(sent)),
			FailedSMSDetails: []any{},
			SentSMSDetails:   sent,
		}},
	})
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("/client/api/sendmessage", sendMessage)
	log.Println("afrosoft-stub on :9001")
	log.Fatal(http.ListenAndServe(":9001", mux))
}
