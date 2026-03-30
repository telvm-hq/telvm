package main

import (
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	// ":3333" listens on all interfaces (VM manager pre-flight probe contract).
	_ = http.ListenAndServe(":3333", nil)
}
