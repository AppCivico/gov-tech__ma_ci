package main

import (
	"bufio"
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
	cmd := exec.Command(deployCmd)

	// Get a pipe to read from standard out
	read, _ := cmd.StdoutPipe()

	// Use the same pipe for standard error
	cmd.Stderr = cmd.Stdout

	// Make a new channel which will be used to ensure we get all output
	done := make(chan struct{})

	// Create a scanner which scans r in a line-by-line fashion
	scanner := bufio.NewScanner(read)

	// Use the scanner to scan the output line by line and log it
	// It's running in a goroutine so that it doesn't block
	go func() {

		// Read line by line and process it
		for scanner.Scan() {
			line := scanner.Text()
			fmt.Fprintln(w, line)
			log.Println(line)

			if f, ok := w.(http.Flusher); ok {
				f.Flush()
			}
		}

		// We're all done, unblock the channel
		done <- struct{}{}

	}()

	// Start the command and check for errors
	err := cmd.Start()

	if err != nil {
		w.WriteHeader(http.StatusAccepted)
		fmt.Fprintln(w, err.Error())
		log.Println(err)
		return
	}

	<-done

	// Wait for all output to be processed
	err = cmd.Wait()

	if err != nil {
		w.WriteHeader(http.StatusAccepted)
		fmt.Fprintln(w, err.Error())
		log.Println(err)
		return
	}

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
