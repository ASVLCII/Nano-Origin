package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func writeBundle(t *testing.T, payload []byte, offset, length uint64, sum [32]byte) *os.File {
	t.Helper()

	path := filepath.Join(t.TempDir(), "bundle.exe")
	b := append([]byte(nil), payload...)
	footerBytes := make([]byte, footerSize)
	copy(footerBytes[:16], magic)
	copy(footerBytes[16:48], "test-bundle")
	binary.LittleEndian.PutUint64(footerBytes[48:56], offset)
	binary.LittleEndian.PutUint64(footerBytes[56:64], length)
	copy(footerBytes[64:96], sum[:])
	b = append(b, footerBytes...)
	if err := os.WriteFile(path, b, 0600); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.Close() })
	return f
}

func TestReadFooterAndVerifyPayload(t *testing.T) {
	payload := []byte("valid payload")
	sum := sha256.Sum256(payload)
	f := writeBundle(t, payload, 0, uint64(len(payload)), sum)

	ft, err := readFooter(f)
	if err != nil {
		t.Fatal(err)
	}
	if ft.Bundle != "test-bundle" || ft.Offset != 0 || ft.Length != uint64(len(payload)) {
		t.Fatalf("unexpected footer: %+v", ft)
	}
	if err := verifyPayload(f, ft); err != nil {
		t.Fatal(err)
	}
}

func TestReadFooterRejectsInvalidBounds(t *testing.T) {
	payload := []byte("payload")
	sum := sha256.Sum256(payload)
	tests := []struct {
		name   string
		offset uint64
		length uint64
	}{
		{name: "empty payload", offset: 0, length: 0},
		{name: "past payload area", offset: uint64(len(payload)), length: 1},
		{name: "integer overflow", offset: math.MaxUint64, length: 2},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f := writeBundle(t, payload, tc.offset, tc.length, sum)
			if _, err := readFooter(f); err == nil {
				t.Fatal("accepted invalid payload bounds")
			}
		})
	}
}

func TestVerifyPayloadRejectsCorruption(t *testing.T) {
	payload := []byte("corrupted payload")
	wrongSum := sha256.Sum256([]byte("original payload"))
	f := writeBundle(t, payload, 0, uint64(len(payload)), wrongSum)
	ft, err := readFooter(f)
	if err != nil {
		t.Fatal(err)
	}
	if err := verifyPayload(f, ft); err == nil {
		t.Fatal("accepted payload with mismatched SHA-256")
	}
}

func TestSafeDestinationRejectsUnsafePaths(t *testing.T) {
	root := filepath.Join(t.TempDir(), "stage")
	for _, name := range []string{
		"../evil",
		"a/../../evil",
		"/absolute",
		`\\server\share\evil`,
		`C:\evil`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := safeDestination(root, name); err == nil {
				t.Fatalf("accepted unsafe path %q", name)
			}
		})
	}
}

func TestSafeDestinationAcceptsNormalPath(t *testing.T) {
	root := filepath.Join(t.TempDir(), "stage")
	want := filepath.Join(root, "runtime", "firefox.exe")
	got, err := safeDestination(root, "runtime/firefox.exe")
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestExtractPayloadRejectsTraversalAndSymlink(t *testing.T) {
	for _, tc := range []struct {
		name string
		path string
		mode os.FileMode
	}{
		{name: "traversal", path: "../outside.txt"},
		{name: "symlink", path: "runtime/link", mode: os.ModeSymlink | 0777},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var archive bytes.Buffer
			zw := zip.NewWriter(&archive)
			header := &zip.FileHeader{Name: tc.path, Method: zip.Store}
			header.SetMode(tc.mode)
			w, err := zw.CreateHeader(header)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = w.Write([]byte("target")); err != nil {
				t.Fatal(err)
			}
			if err = zw.Close(); err != nil {
				t.Fatal(err)
			}

			payload := archive.Bytes()
			f := writeBundle(t, payload, 0, uint64(len(payload)), sha256.Sum256(payload))
			stage := filepath.Join(t.TempDir(), "stage")
			if err = os.MkdirAll(stage, 0700); err != nil {
				t.Fatal(err)
			}
			if err = extractPayload(f, footer{Offset: 0, Length: uint64(len(payload))}, stage); err == nil {
				t.Fatalf("accepted unsafe ZIP entry %q", tc.path)
			}
		})
	}
}

func TestPrepareRecoversCacheAndPreservesProfile(t *testing.T) {
	var archive bytes.Buffer
	zw := zip.NewWriter(&archive)
	for name, body := range map[string]string{
		"runtime/nano-origin-browser.exe": "new runtime",
		"profile-seed/user.js":            "seed profile",
	} {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = w.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	payload := archive.Bytes()
	sum := sha256.Sum256(payload)
	f := writeBundle(t, payload, 0, uint64(len(payload)), sum)
	ft, err := readFooter(f)
	if err != nil {
		t.Fatal(err)
	}

	root := t.TempDir()
	profile := filepath.Join(root, "profile")
	if err = os.MkdirAll(profile, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(profile, "bookmarks-preserved")
	if err = os.WriteFile(marker, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	old := filepath.Join(root, ".runtime-old")
	if err = os.MkdirAll(old, 0700); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(old, "old-runtime"), []byte("old"), 0600); err != nil {
		t.Fatal(err)
	}
	stale := filepath.Join(root, ".staging-stale")
	if err = os.MkdirAll(stale, 0700); err != nil {
		t.Fatal(err)
	}

	if err = prepare(f, ft, root); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(filepath.Join(root, "runtime", "nano-origin-browser.exe")); err != nil {
		t.Fatalf("new runtime was not activated: %v", err)
	}
	if _, err = os.Stat(marker); err != nil {
		t.Fatalf("existing profile was not preserved: %v", err)
	}
	if _, err = os.Stat(filepath.Join(profile, "user.js")); !os.IsNotExist(err) {
		t.Fatal("existing profile was overwritten by the seed")
	}
	if _, err = os.Stat(stale); !os.IsNotExist(err) {
		t.Fatal("stale staging directory was not removed")
	}
	if got, err := os.ReadFile(filepath.Join(root, "bundle-id")); err != nil || string(got) != "test-bundle" {
		t.Fatalf("bundle marker mismatch: %q, %v", got, err)
	}
}

func TestPrepareSeedsNewProfile(t *testing.T) {
	var archive bytes.Buffer
	zw := zip.NewWriter(&archive)
	for name, body := range map[string]string{
		"runtime/nano-origin-browser.exe": "runtime",
		"profile-seed/user.js":            "seed",
	} {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = w.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	payload := archive.Bytes()
	f := writeBundle(t, payload, 0, uint64(len(payload)), sha256.Sum256(payload))
	ft, err := readFooter(f)
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	if err = prepare(f, ft, root); err != nil {
		t.Fatal(err)
	}
	if got, err := os.ReadFile(filepath.Join(root, "profile", "user.js")); err != nil || string(got) != "seed" {
		t.Fatalf("profile seed mismatch: %q, %v", got, err)
	}
}
