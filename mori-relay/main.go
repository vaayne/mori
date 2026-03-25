package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	addr := flag.String("addr", "", "listen address (e.g. :19820)")
	flag.Parse()

	listenAddr := *addr
	if listenAddr == "" {
		if port := os.Getenv("PORT"); port != "" {
			listenAddr = ":" + port
		} else {
			listenAddr = ":19820"
		}
	}

	relay := NewRelay()

	mux := http.NewServeMux()
	mux.HandleFunc("POST /pair", relay.HandlePair)
	mux.HandleFunc("GET /ws", relay.HandleWS)
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	srv := &http.Server{
		Addr:         listenAddr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("relay listening on %s", listenAddr)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
	log.Println("relay shut down")
}
