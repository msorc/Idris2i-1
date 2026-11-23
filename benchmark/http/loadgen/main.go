// Command loadgen is a closed-loop HTTP/1.1 load generator: each of N
// persistent connections sends a request, reads the whole response, and
// sends the next one, for a fixed duration. It speaks just enough HTTP for
// a benchmark (Content-Length responses), so that the generator itself
// costs little next to the server under test.
//
//	loadgen -addr 127.0.0.1:8080 -conns 64 -duration 10s -path /hello
//	loadgen -addr 127.0.0.1:8080 -method POST -path /json -body body.json
//	loadgen -addr 127.0.0.1:8080 -idle 5000 -hold 10s   (idle connections)
//	loadgen -addr 127.0.0.1:8443 -tls -path /hello      (HTTPS, any certificate)
//	loadgen -addr 127.0.0.1:8443 -h2 -conns 1 -streams 64   (HTTP/2 over TLS)
package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

type config struct {
	addr     string
	conns    int
	duration time.Duration
	method   string
	path     string
	bodyFile string
	idle     int
	hold     time.Duration
	tls      bool
	h2       bool
	streams  int
}

func main() {
	var cfg config
	flag.StringVar(&cfg.addr, "addr", "127.0.0.1:8080", "server address")
	flag.IntVar(&cfg.conns, "conns", 64, "number of persistent connections")
	flag.DurationVar(&cfg.duration, "duration", 10*time.Second, "length of the run")
	flag.StringVar(&cfg.method, "method", "GET", "request method")
	flag.StringVar(&cfg.path, "path", "/hello", "request target")
	flag.StringVar(&cfg.bodyFile, "body", "", "file with the request body")
	flag.IntVar(&cfg.idle, "idle", 0, "open this many idle connections instead, and hold them")
	flag.DurationVar(&cfg.hold, "hold", 10*time.Second, "how long to hold idle connections")
	flag.BoolVar(&cfg.tls, "tls", false, "speak HTTPS (HTTP/1.1 over TLS, without verifying the server)")
	flag.BoolVar(&cfg.h2, "h2", false, "speak HTTP/2 over TLS with net/http (without verifying the server)")
	flag.IntVar(&cfg.streams, "streams", 1, "with -h2: requests at a time on each connection")
	flag.Parse()

	if err := run(context.Background(), cfg); err != nil {
		fmt.Fprintln(os.Stderr, "loadgen:", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, cfg config) error {
	if cfg.idle > 0 {
		return holdIdle(ctx, cfg)
	}
	if cfg.h2 {
		return runH2(ctx, cfg)
	}
	var body []byte
	if cfg.bodyFile != "" {
		b, err := os.ReadFile(cfg.bodyFile)
		if err != nil {
			return fmt.Errorf("read body: %w", err)
		}
		body = b
	}
	req := fmt.Appendf(nil, "%s %s HTTP/1.1\r\nHost: %s\r\n", cfg.method, cfg.path, cfg.addr)
	if body != nil {
		req = fmt.Appendf(req, "Content-Type: application/json\r\nContent-Length: %d\r\n", len(body))
	}
	req = append(req, "\r\n"...)
	req = append(req, body...)

	ctx, cancel := context.WithTimeout(ctx, cfg.duration)
	defer cancel()

	var done, failed atomic.Int64
	var wg sync.WaitGroup
	start := time.Now()
	for range cfg.conns {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := loop(ctx, cfg.addr, cfg.tls, req, &done); err != nil {
				failed.Add(1)
				fmt.Fprintln(os.Stderr, "connection:", err)
			}
		}()
	}
	wg.Wait()
	elapsed := time.Since(start).Seconds()
	n := done.Load()
	fmt.Printf("requests %d seconds %.2f rps %.0f failed_conns %d\n", n, elapsed, float64(n)/elapsed, failed.Load())
	return nil
}

// loop sends requests on one connection until the context ends.
func loop(ctx context.Context, addr string, useTLS bool, req []byte, done *atomic.Int64) error {
	c, err := dial(ctx, addr, useTLS)
	if err != nil {
		return err
	}
	defer c.Close()
	go func() { <-ctx.Done(); c.SetDeadline(time.Now()) }()
	r := bufio.NewReaderSize(c, 64<<10)
	for ctx.Err() == nil {
		if _, err := c.Write(req); err != nil {
			return ignoreEnd(ctx, err)
		}
		if err := readResponse(r); err != nil {
			return ignoreEnd(ctx, err)
		}
		done.Add(1)
	}
	return nil
}

// dial connects, and runs the handshake of TLS if asked.
func dial(ctx context.Context, addr string, useTLS bool) (net.Conn, error) {
	var d net.Dialer
	c, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("dial: %w", err)
	}
	if !useTLS {
		return c, nil
	}
	tc := tls.Client(c, &tls.Config{InsecureSkipVerify: true, NextProtos: []string{"http/1.1"}})
	if err := tc.HandshakeContext(ctx); err != nil {
		c.Close()
		return nil, fmt.Errorf("handshake: %w", err)
	}
	return tc, nil
}

func ignoreEnd(ctx context.Context, err error) error {
	if ctx.Err() != nil {
		return nil
	}
	return err
}

var errNoLength = errors.New("response without Content-Length")

// readResponse reads a response head and its Content-Length body.
func readResponse(r *bufio.Reader) error {
	length := -1
	first := true
	for {
		line, err := r.ReadSlice('\n')
		if err != nil {
			return fmt.Errorf("read head: %w", err)
		}
		line = bytes.TrimRight(line, "\r\n")
		if len(line) == 0 {
			break
		}
		if first {
			first = false
			if !bytes.HasPrefix(line, []byte("HTTP/1.1 200")) && !bytes.HasPrefix(line, []byte("HTTP/1.1 201")) {
				return fmt.Errorf("status line %q", line)
			}
			continue
		}
		name, value, ok := bytes.Cut(line, []byte(":"))
		if ok && bytes.EqualFold(name, []byte("Content-Length")) {
			n, err := strconv.Atoi(string(bytes.TrimSpace(value)))
			if err != nil {
				return fmt.Errorf("content length: %w", err)
			}
			length = n
		}
	}
	if length < 0 {
		return errNoLength
	}
	if _, err := r.Discard(length); err != nil {
		return fmt.Errorf("read body: %w", err)
	}
	return nil
}

// holdIdle opens idle persistent connections (one request each, so that
// the server has served them) and holds them open.
func holdIdle(ctx context.Context, cfg config) error {
	req := fmt.Appendf(nil, "GET %s HTTP/1.1\r\nHost: %s\r\n\r\n", cfg.path, cfg.addr)
	conns := make([]net.Conn, 0, cfg.idle)
	defer func() {
		for _, c := range conns {
			c.Close()
		}
	}()
	var d net.Dialer
	for range cfg.idle {
		c, err := d.DialContext(ctx, "tcp", cfg.addr)
		if err != nil {
			return fmt.Errorf("dial after %d: %w", len(conns), err)
		}
		conns = append(conns, c)
		if _, err := c.Write(req); err != nil {
			return fmt.Errorf("write: %w", err)
		}
		if err := readResponse(bufio.NewReader(c)); err != nil && !errors.Is(err, io.EOF) {
			return fmt.Errorf("response: %w", err)
		}
	}
	fmt.Printf("holding %d idle connections\n", len(conns))
	select {
	case <-ctx.Done():
	case <-time.After(cfg.hold):
	}
	return nil
}

// runH2 runs closed loops of HTTP/2 requests over TLS: `conns` connections
// (a transport of net/http each, allowed one connection), each carrying
// `streams` requests at a time.
func runH2(ctx context.Context, cfg config) error {
	var body []byte
	if cfg.bodyFile != "" {
		b, err := os.ReadFile(cfg.bodyFile)
		if err != nil {
			return fmt.Errorf("read body: %w", err)
		}
		body = b
	}
	url := "https://" + cfg.addr + cfg.path
	ctx, cancel := context.WithTimeout(ctx, cfg.duration)
	defer cancel()
	var done, failed atomic.Int64
	var wg sync.WaitGroup
	start := time.Now()
	for range cfg.conns {
		tr := &http.Transport{
			TLSClientConfig:   &tls.Config{InsecureSkipVerify: true},
			ForceAttemptHTTP2: true,
			MaxConnsPerHost:   1,
		}
		client := &http.Client{Transport: tr}
		for range cfg.streams {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for ctx.Err() == nil {
					var rd io.Reader
					if body != nil {
						rd = bytes.NewReader(body)
					}
					req, _ := http.NewRequestWithContext(ctx, cfg.method, url, rd)
					if body != nil {
						req.Header.Set("Content-Type", "application/json")
					}
					resp, err := client.Do(req)
					if err != nil {
						if ctx.Err() == nil {
							failed.Add(1)
						}
						return
					}
					io.Copy(io.Discard, resp.Body)
					resp.Body.Close()
					if resp.ProtoMajor != 2 {
						failed.Add(1)
						return
					}
					done.Add(1)
				}
			}()
		}
	}
	wg.Wait()
	elapsed := time.Since(start).Seconds()
	n := done.Load()
	fmt.Printf("requests %d seconds %.2f rps %.0f failed_conns %d\n", n, elapsed, float64(n)/elapsed, failed.Load())
	return nil
}
