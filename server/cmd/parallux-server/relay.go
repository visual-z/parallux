package main

import "errors"

// The relay role (中继主机, PLAN decision 24). stubs: feat-relay-links

// RelayMethod is the only cipher a relay speaks.
const RelayMethod = "2022-blake3-aes-128-gcm"

// RelayOptions are the knobs of the relay configuration.
type RelayOptions struct {
	Listen   string
	Port     uint16
	Key      string
	LogLevel string
}

// RelayConfig builds the relay's sing-box configuration. stub
func RelayConfig(o RelayOptions) ([]byte, error) {
	return nil, errors.New("relay: not implemented")
}

// NewRelayKey generates a relay key. stub
func NewRelayKey() (string, error) {
	return "", nil
}

// RelayLink is the import link the app takes. stub
func RelayLink(host string, port uint16, key, name string) string {
	return ""
}
