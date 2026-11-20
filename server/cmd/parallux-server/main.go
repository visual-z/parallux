// Command parallux-server is the aggregation server (聚合服务器, PLAN
// decision 18): it accepts the legs of a bonded connection on a multipath
// inbound, reassembles them, and sends the stream on through a direct
// outbound.
//
// With -role relay it is a relay host instead (中继主机, decision 24): see
// relay.go.
//
// It runs from a full sing-box configuration file (-config), or builds the
// minimal one from flags. The pre-shared key is read from a file only, so it
// never appears in the process list, and it is never logged.
//
//	parallux-server -config /etc/parallux-server/config.json
//	parallux-server -port 39000 -psk-file /etc/parallux-server/psk [-listen ::] [-allowed-ips 198.51.100.0/24]
package main

import (
	"context"
	stdjson "encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"strings"
	"syscall"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"

	"github.com/visual-z/parallux/core/bond"
)

// Version is set by release builds: -ldflags "-X main.Version=…".
var Version = "0.0.0-dev"

const (
	roleAggregation = "aggregation"
	roleRelay       = "relay"
)

// stdout is where -link and -version print; tests replace it.
var stdout io.Writer = os.Stdout

// minPSKLength: shorter keys are guessable; upstream recommends a long random
// string, and install.sh generates 43 characters (32 random bytes, base64url).
const minPSKLength = 16

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "parallux-server:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	flags := flag.NewFlagSet("parallux-server", flag.ContinueOnError)
	configPath := flags.String("config", "", "sing-box configuration file (overrides the other flags)")
	listen := flags.String("listen", "::", "listen address")
	port := flags.Uint("port", 39000, "listen port")
	pskFile := flags.String("psk-file", "", "file holding the pre-shared key")
	allowed := flags.String("allowed-ips", "", "comma-separated client prefixes allowed to connect")
	logLevel := flags.String("log-level", "info", "log level")
	check := flags.Bool("check", false, "validate the configuration and exit")
	version := flags.Bool("version", false, "print the version and exit")
	role := flags.String("role", roleAggregation, "aggregation or relay")
	keyFile := flags.String("key-file", "", "relay: file holding the relay key")
	generateKey := flags.Bool("generate-key", false, "relay: write a new key to -key-file unless it exists, then exit")
	printLink := flags.Bool("link", false, "relay: print the import link for -host and exit")
	host := flags.String("host", "", "relay: the address the Mac reaches this machine at, for -link")
	name := flags.String("name", "", "relay: display name for -link")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *version {
		fmt.Fprintln(stdout, "parallux-server", Version)
		return nil
	}
	if *role != roleAggregation && *role != roleRelay {
		return fmt.Errorf("unknown role %q, want %s or %s", *role, roleAggregation, roleRelay)
	}
	if *role == roleRelay && *generateKey {
		return generateRelayKey(*keyFile)
	}
	// -port's default is the aggregation server's; a relay has its own.
	portSet := false
	flags.Visit(func(f *flag.Flag) { portSet = portSet || f.Name == "port" })
	if *role == roleRelay && !portSet {
		*port = defaultRelayPort
	}
	if *port == 0 || *port > 65535 {
		return fmt.Errorf("port %d is not 1–65535", *port)
	}
	if *role == roleRelay && *printLink {
		if *host == "" {
			return errors.New("-link needs -host, the address the Mac reaches this machine at")
		}
		key, err := readRelayKey(*keyFile)
		if err != nil {
			return err
		}
		fmt.Fprintln(stdout, RelayLink(*host, uint16(*port), key, *name))
		return nil
	}

	var content []byte
	var err error
	if *configPath != "" {
		content, err = os.ReadFile(*configPath)
		if err != nil {
			return fmt.Errorf("read config: %w", err)
		}
	} else if *role == roleRelay {
		key, err := readRelayKey(*keyFile)
		if err != nil {
			return err
		}
		content, err = RelayConfig(RelayOptions{Listen: *listen, Port: uint16(*port), Key: key, LogLevel: *logLevel})
		if err != nil {
			return err
		}
	} else {
		psk, err := readPSK(*pskFile)
		if err != nil {
			return err
		}
		content, err = Config(ConfigOptions{Listen: *listen, Port: uint16(*port), PSK: psk, AllowedIPs: splitList(*allowed), LogLevel: *logLevel})
		if err != nil {
			return err
		}
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	ctx = include.Context(ctx)
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, content)
	if err != nil {
		return fmt.Errorf("decode config: %w", err)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return fmt.Errorf("create service: %w", err)
	}
	if *check {
		return instance.Close()
	}
	if err := instance.Start(); err != nil {
		instance.Close()
		return fmt.Errorf("start service: %w", err)
	}
	<-ctx.Done()
	return instance.Close()
}

func readPSK(path string) (string, error) {
	if path == "" {
		return "", errors.New("-psk-file is required without -config")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read psk file: %w", err)
	}
	psk := strings.TrimSpace(string(data))
	if len(psk) < minPSKLength {
		return "", fmt.Errorf("psk in %s is shorter than %d characters", path, minPSKLength)
	}
	return psk, nil
}

func splitList(value string) []string {
	var out []string
	for _, item := range strings.Split(value, ",") {
		if item = strings.TrimSpace(item); item != "" {
			out = append(out, item)
		}
	}
	return out
}

// ConfigOptions are the knobs of the minimal server configuration.
type ConfigOptions struct {
	Listen     string
	Port       uint16
	PSK        string
	AllowedIPs []string
	LogLevel   string
}

// Config builds the minimal server configuration: one multipath inbound and
// one direct outbound.
func Config(o ConfigOptions) ([]byte, error) {
	if o.Port == 0 {
		return nil, errors.New("port must not be 0")
	}
	if len(o.PSK) < minPSKLength {
		return nil, fmt.Errorf("psk is shorter than %d characters", minPSKLength)
	}
	inbound := map[string]any{
		"type":        bond.Type,
		"tag":         "mp-in",
		"listen":      o.Listen,
		"listen_port": o.Port,
		"psk":         o.PSK,
	}
	if len(o.AllowedIPs) > 0 {
		inbound["allowed_ips"] = o.AllowedIPs
	}
	level := o.LogLevel
	if level == "" {
		level = "info"
	}
	return stdjson.MarshalIndent(map[string]any{
		"log":       map[string]any{"level": level, "timestamp": true},
		"inbounds":  []any{inbound},
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}},
	}, "", "  ")
}
