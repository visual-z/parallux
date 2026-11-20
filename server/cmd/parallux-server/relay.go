package main

import (
	"crypto/rand"
	"encoding/base64"
	stdjson "encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
)

// The relay role (中继主机, PLAN decision 24): a machine on the user's LAN
// that dials out for the Mac, so each relay host adds its own egress quota.
// It is sing-box's stock shadowsocks 2022 inbound in front of a direct
// outbound; nothing here is Parallux's own protocol (PLAN §2).
//
//	parallux-server -role relay -key-file /etc/parallux-server/relay.key -generate-key
//	parallux-server -role relay -port 39100 -key-file /etc/parallux-server/relay.key
//	parallux-server -role relay -port 39100 -key-file … -host 10.0.0.21 -name worker-1 -link

// RelayMethod is the only cipher a relay speaks. Why this one: no
// certificate to manage, authenticated with replay protection (the LAN is
// shared, an open forwarder would be anyone's jump host), carries TCP and
// UDP; AES is hardware-accelerated on the nodes and the Mac.
const RelayMethod = "2022-blake3-aes-128-gcm"

// relayKeyBytes is the key length RelayMethod requires.
const relayKeyBytes = 16

// defaultRelayPort keeps a relay off the aggregation server's 39000, so one
// machine can run both roles.
const defaultRelayPort = 39100

// RelayOptions are the knobs of the relay configuration.
type RelayOptions struct {
	Listen   string
	Port     uint16
	Key      string
	LogLevel string
}

// checkRelayKey accepts exactly what sing-box's shadowsocks 2022 accepts:
// padded standard base64 of relayKeyBytes bytes (measured on loopback,
// docs/tasks/feat-relay-links.md). Its errors never quote the key.
func checkRelayKey(key string) error {
	raw, err := base64.StdEncoding.DecodeString(key)
	if err != nil {
		return errors.New("the relay key is not padded standard base64")
	}
	if len(raw) != relayKeyBytes {
		return fmt.Errorf("the relay key decodes to %d bytes, want %d", len(raw), relayKeyBytes)
	}
	return nil
}

// RelayConfig builds the relay's sing-box configuration: one shadowsocks
// inbound and one direct outbound.
func RelayConfig(o RelayOptions) ([]byte, error) {
	if o.Port == 0 {
		return nil, errors.New("port must not be 0")
	}
	if err := checkRelayKey(o.Key); err != nil {
		return nil, err
	}
	listen := o.Listen
	if listen == "" {
		listen = "::"
	}
	level := o.LogLevel
	if level == "" {
		level = "info"
	}
	return stdjson.MarshalIndent(map[string]any{
		"log": map[string]any{"level": level, "timestamp": true},
		"inbounds": []any{map[string]any{
			"type":        "shadowsocks",
			"tag":         "relay-in",
			"listen":      listen,
			"listen_port": o.Port,
			"method":      RelayMethod,
			"password":    o.Key,
		}},
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}},
	}, "", "  ")
}

// NewRelayKey generates a relay key: relayKeyBytes random bytes in padded
// standard base64.
func NewRelayKey() (string, error) {
	raw := make([]byte, relayKeyBytes)
	if _, err := rand.Read(raw); err != nil {
		return "", fmt.Errorf("generate relay key: %w", err)
	}
	return base64.StdEncoding.EncodeToString(raw), nil
}

// RelayLink is the import link the app takes (docs/research/relay-link.md,
// version 1). Values are percent-encoded as RFC 3986 query components, so
// the key's "+", "/" and "=" never travel raw.
func RelayLink(host string, port uint16, key, name string) string {
	link := "parallux://relay?v=1&host=" + escapeComponent(host) +
		"&port=" + strconv.Itoa(int(port)) +
		"&method=" + escapeComponent(RelayMethod) +
		"&key=" + escapeComponent(key)
	if name != "" {
		link += "#" + escapeComponent(name)
	}
	return link
}

// escapeComponent percent-encodes everything but RFC 3986 unreserved
// characters. url.QueryEscape differs only in writing a space as "+", which
// the link format reserves for a literal plus.
func escapeComponent(value string) string {
	return strings.ReplaceAll(url.QueryEscape(value), "+", "%20")
}

// readRelayKey reads and validates the key file.
func readRelayKey(path string) (string, error) {
	if path == "" {
		return "", errors.New("-key-file is required with -role relay")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read key file: %w", err)
	}
	key := strings.TrimSpace(string(data))
	if err := checkRelayKey(key); err != nil {
		return "", fmt.Errorf("%s: %w", path, err)
	}
	return key, nil
}

// generateRelayKey writes a new key to path unless a file is already there:
// reinstalling a relay must not invalidate the link the app already has.
func generateRelayKey(path string) error {
	if path == "" {
		return errors.New("-key-file is required with -generate-key")
	}
	key, err := NewRelayKey()
	if err != nil {
		return err
	}
	// O_EXCL: never overwrite, and never follow a file someone else put there.
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if errors.Is(err, os.ErrExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("create key file: %w", err)
	}
	if _, err := file.WriteString(key + "\n"); err != nil {
		file.Close()
		return fmt.Errorf("write key file: %w", err)
	}
	return file.Close()
}
