// Local TCP SOCKS5 bridge to the official AmneziaWG userspace network stack.
// No kernel interface, DNS settings, routes, or firewall rules are changed.
package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/netip"
	"os"
	"strings"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"
)

func config(path string) ([]netip.Addr, []netip.Addr, string, error) {
	f, e := os.Open(path)
	if e != nil {
		return nil, nil, "", e
	}
	defer f.Close()
	var addresses, dns []netip.Addr
	var ipc strings.Builder
	section := ""
	fields := map[string]string{"privatekey": "private_key", "publickey": "public_key", "presharedkey": "preshared_key", "headerprotectionkey": "header_protection_key", "persistentkeepalive": "persistent_keepalive_interval", "rekeyaftertime": "rekey_after_time", "rekeytimeout": "rekey_timeout", "rejectaftertime": "reject_after_time", "keepalivetimeout": "keepalive_timeout", "maxhandshakeattempts": "max_handshake_attempts", "contentpaddingaddition": "content_padding_addition"}
	scan := bufio.NewScanner(f)
	for scan.Scan() {
		line := strings.TrimSpace(scan.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			section = strings.ToLower(line)
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			return nil, nil, "", errors.New("invalid line")
		}
		k = strings.ToLower(strings.TrimSpace(k))
		v = strings.TrimSpace(v)
		if k == "address" || k == "dns" {
			for _, item := range strings.Split(v, ",") {
				item = strings.TrimSpace(item)
				if k == "address" {
					a, e := netip.ParsePrefix(item)
					if e != nil {
						return nil, nil, "", e
					}
					addresses = append(addresses, a.Addr())
				} else {
					a, e := netip.ParseAddr(item)
					if e != nil {
						return nil, nil, "", e
					}
					dns = append(dns, a)
				}
			}
			continue
		}
		if k == "mtu" {
			continue
		}
		if k == "allowedips" {
			for _, item := range strings.Split(v, ",") {
				if _, e := netip.ParsePrefix(strings.TrimSpace(item)); e != nil {
					return nil, nil, "", e
				}
				fmt.Fprintf(&ipc, "allowed_ip=%s\n", strings.TrimSpace(item))
			}
			continue
		}
		mapped, known := fields[k]
		if !known {
			mapped = k
			known = k == "endpoint" || k == "jc" || k == "jmin" || k == "jmax" || k == "s1" || k == "s2" || k == "s3" || k == "s4" || k == "h1" || k == "h2" || k == "h3" || k == "h4" || k == "i1" || k == "i2" || k == "i3" || k == "i4" || k == "i5"
		}
		if !known {
			return nil, nil, "", errors.New("unsupported field")
		}
		if strings.HasSuffix(mapped, "_key") {
			b, e := base64.StdEncoding.DecodeString(v)
			if e != nil || len(b) != 32 {
				return nil, nil, "", errors.New("invalid key")
			}
			v = hex.EncodeToString(b)
		}
		if mapped == "endpoint" {
			addr, e := net.ResolveUDPAddr("udp", v)
			if e != nil {
				return nil, nil, "", e
			}
			v = addr.String()
		}
		if section != "[interface]" && section != "[peer]" {
			return nil, nil, "", errors.New("invalid section")
		}
		fmt.Fprintf(&ipc, "%s=%s\n", mapped, v)
	}
	if e := scan.Err(); e != nil {
		return nil, nil, "", e
	}
	if len(addresses) == 0 || len(dns) == 0 {
		return nil, nil, "", errors.New("missing address or DNS")
	}
	return addresses, dns, ipc.String(), nil
}

type dialer interface {
	DialContext(context.Context, string, string) (net.Conn, error)
}

func serve(client net.Conn, network dialer) {
	defer client.Close()
	client.SetDeadline(time.Now().Add(15 * time.Second))
	r := bufio.NewReader(client)
	header := make([]byte, 2)
	if _, e := io.ReadFull(r, header); e != nil || header[0] != 5 {
		return
	}
	methods := make([]byte, int(header[1]))
	if _, e := io.ReadFull(r, methods); e != nil {
		return
	}
	noauth := false
	for _, m := range methods {
		if m == 0 {
			noauth = true
		}
	}
	if !noauth {
		client.Write([]byte{5, 255})
		return
	}
	if _, e := client.Write([]byte{5, 0}); e != nil {
		return
	}
	request := make([]byte, 4)
	if _, e := io.ReadFull(r, request); e != nil || request[0] != 5 || request[1] != 1 || request[2] != 0 {
		return
	}
	var host string
	switch request[3] {
	case 1:
		b := make([]byte, 4)
		if _, e := io.ReadFull(r, b); e != nil {
			return
		}
		host = net.IP(b).String()
	case 4:
		b := make([]byte, 16)
		if _, e := io.ReadFull(r, b); e != nil {
			return
		}
		host = net.IP(b).String()
	case 3:
		n, e := r.ReadByte()
		if e != nil || n == 0 {
			return
		}
		b := make([]byte, int(n))
		if _, e := io.ReadFull(r, b); e != nil {
			return
		}
		host = string(b)
	default:
		return
	}
	port := make([]byte, 2)
	if _, e := io.ReadFull(r, port); e != nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	remote, e := network.DialContext(ctx, "tcp", net.JoinHostPort(host, fmt.Sprint(int(port[0])*256+int(port[1]))))
	if e != nil {
		client.Write([]byte{5, 4, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	defer remote.Close()
	if _, e := client.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); e != nil {
		return
	}
	client.SetDeadline(time.Time{})
	done := make(chan struct{}, 1)
	go func() { io.Copy(remote, r); done <- struct{}{} }()
	go func() { io.Copy(client, remote); done <- struct{}{} }()
	<-done
}

func main() {
	path := flag.String("config", "", "private AWG .conf")
	listen := flag.String("listen", "127.0.0.1:10932", "loopback SOCKS address")
	check := flag.Bool("check", false, "validate file without starting network")
	flag.Parse()
	host, _, e := net.SplitHostPort(*listen)
	if e != nil || host != "127.0.0.1" {
		log.Fatal("Only IPv4 loopback listeners are allowed")
	}
	addresses, dns, ipc, e := config(*path)
	if e != nil {
		log.Fatal("Private config is invalid")
	}
	if *check {
		fmt.Println("Config parsed")
		return
	}
	tun, network, e := netstack.CreateNetTUN(addresses, dns, 1280)
	if e != nil {
		log.Fatal("Network stack could not start")
	}
	dev := device.NewDevice(tun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	defer dev.Close()
	if e = dev.IpcSet(ipc); e != nil {
		log.Fatal("AWG config rejected")
	}
	if e = dev.Up(); e != nil {
		log.Fatal("AWG could not start")
	}
	listener, e := net.Listen("tcp", *listen)
	if e != nil {
		log.Fatal("SOCKS listener could not start")
	}
	defer listener.Close()
	fmt.Println("AWG SOCKS ready on loopback")
	slots := make(chan struct{}, 64)
	for {
		c, e := listener.Accept()
		if e != nil {
			return
		}
		select {
		case slots <- struct{}{}:
			go func() { defer func() { <-slots }(); serve(c, network) }()
		default:
			c.Close()
		}
	}
}
