package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sync"
)

var mu sync.Mutex
var listenAddr = os.Getenv("LISTEN_ADDR")
var deployCmd = os.Getenv("DEPLOY_CMD")

func deployHandler(w http.ResponseWriter, r *http.Request) {
	mu.Lock()
	defer mu.Unlock()
	defer log.Println("request finished")
	log.Println("running " + deployCmd)
	out, err := exec.Command(deployCmd).Output()

	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprintln(w, err.Error())
		log.Println(err)
		return
	}

	w.WriteHeader(http.StatusOK)
	log.Println(string(out))
	fmt.Fprintln(w, string(out))
}

func catchAllHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusNotFound)
	fmt.Fprint(w, "")
}

func main() {
	http.HandleFunc("/deploy", deployHandler)
	http.HandleFunc("/", catchAllHandler)

	log.Fatal(http.ListenAndServe(listenAddr, nil))
}
