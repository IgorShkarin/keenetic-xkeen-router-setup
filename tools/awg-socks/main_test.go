package main

import (
	"context"
	"encoding/base64"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigPreservesAWG3AndRejectsUnknownFields(t *testing.T) {
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	path := filepath.Join(t.TempDir(), "private.conf")
	configText := "[Interface]\nAddress=10.0.0.2/32\nDNS=10.0.0.1\nPrivateKey=" + key + "\nHeaderProtectionKey=" + key + "\nS3=4\nH1=100-200\n[Peer]\nPublicKey=" + key + "\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=127.0.0.1:12345\n"
	if e := os.WriteFile(path, []byte(configText), 0600); e != nil {
		t.Fatal(e)
	}
	addr, dns, ipc, e := config(path)
	if e != nil {
		t.Fatal(e)
	}
	if len(addr) != 1 || len(dns) != 1 || !strings.Contains(ipc, "header_protection_key=") || !strings.Contains(ipc, "h1=100-200") || !strings.Contains(ipc, "allowed_ip=::/0") {
		t.Fatal("AWG3 settings were lost")
	}
	os.WriteFile(path, []byte(configText+"UnknownSecurityField=1\n"), 0600)
	if _, _, _, e = config(path); e == nil {
		t.Fatal("unknown security field silently accepted")
	}
}

type fakeDialer struct{ target string }

func (d *fakeDialer) DialContext(_ context.Context, network, address string) (net.Conn, error) {
	d.target = address
	a, b := net.Pipe()
	go func() { defer b.Close(); buf := make([]byte, 4); io.ReadFull(b, buf); b.Write(buf) }()
	return a, nil
}
func TestSOCKSDomainIsResolvedInsideTunnelAndCarriesBytes(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	d := &fakeDialer{}
	done := make(chan struct{})
	go func() { serve(server, d); close(done) }()
	client.Write([]byte{5, 1, 0})
	reply := make([]byte, 2)
	if _, e := io.ReadFull(client, reply); e != nil || reply[1] != 0 {
		t.Fatal("greeting")
	}
	host := "example.invalid"
	request := append([]byte{5, 1, 0, 3, byte(len(host))}, []byte(host)...)
	request = append(request, 1, 187)
	client.Write(request)
	response := make([]byte, 10)
	if _, e := io.ReadFull(client, response); e != nil || response[1] != 0 {
		t.Fatal("connect reply")
	}
	client.Write([]byte("test"))
	buf := make([]byte, 4)
	if _, e := io.ReadFull(client, buf); e != nil || string(buf) != "test" {
		t.Fatal("transfer failed")
	}
	client.Close()
	<-done
	if d.target != "example.invalid:443" {
		t.Fatal("DNS escaped tunnel or port corrupted")
	}
}
func TestSOCKSRejectsClientsWithoutNoAuth(t *testing.T) {
	a, b := net.Pipe()
	defer a.Close()
	go serve(b, &fakeDialer{})
	a.Write([]byte{5, 1, 2})
	reply := make([]byte, 2)
	io.ReadFull(a, reply)
	if reply[1] != 255 {
		t.Fatal("unsupported authentication accepted")
	}
}
