package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const (
	productName = "Nano Origin"
	footerSize  = 96
	magic       = "NANOORIGINPKG1!!"
	wmClose     = 0x0010
	pmRemove    = 0x0001
	maxUnpacked = uint64(4 << 30)
	moveReplace = 0x00000001
	moveThrough = 0x00000008
	waitObject0 = 0x00000000
	waitAbandon = 0x00000080
)

var (
	user32               = syscall.NewLazyDLL("user32.dll")
	comctl32             = syscall.NewLazyDLL("comctl32.dll")
	kernel32             = syscall.NewLazyDLL("kernel32.dll")
	procCreateWindowEx   = user32.NewProc("CreateWindowExW")
	procDestroyWindow    = user32.NewProc("DestroyWindow")
	procShowWindow       = user32.NewProc("ShowWindow")
	procUpdateWindow     = user32.NewProc("UpdateWindow")
	procPeekMessage      = user32.NewProc("PeekMessageW")
	procTranslateMsg     = user32.NewProc("TranslateMessage")
	procDispatchMsg      = user32.NewProc("DispatchMessageW")
	procMessageBox       = user32.NewProc("MessageBoxW")
	procSetWindowPos     = user32.NewProc("SetWindowPos")
	procGetSystemMetrics = user32.NewProc("GetSystemMetrics")
	procInitControls     = comctl32.NewProc("InitCommonControls")
	procCreateMutex      = kernel32.NewProc("CreateMutexW")
	procWaitForObject    = kernel32.NewProc("WaitForSingleObject")
	procReleaseMutex     = kernel32.NewProc("ReleaseMutex")
	procCloseHandle      = kernel32.NewProc("CloseHandle")
	procMoveFileEx       = kernel32.NewProc("MoveFileExW")
)

type footer struct {
	Bundle string
	Offset uint64
	Length uint64
	SHA    [32]byte
}

type msg struct {
	Hwnd, Message, WParam, LParam, Time uintptr
	PtX, PtY                            int32
}

func utf16(s string) *uint16 { p, _ := syscall.UTF16PtrFromString(s); return p }

func messageBox(title, text string, flags uintptr) {
	procMessageBox.Call(0, uintptr(unsafe.Pointer(utf16(text))), uintptr(unsafe.Pointer(utf16(title))), flags)
}

func acquireCacheLock() (func(), error) {
	h, _, callErr := procCreateMutex.Call(0, 0, uintptr(unsafe.Pointer(utf16(`Local\NanoOriginCache`))))
	if h == 0 {
		return nil, fmt.Errorf("cannot create cache lock: %w", callErr)
	}
	wait, _, waitErr := procWaitForObject.Call(h, 120000)
	if wait != waitObject0 && wait != waitAbandon {
		procCloseHandle.Call(h)
		if wait == 0x102 {
			return nil, errors.New("another Nano Origin launch is still preparing the browser")
		}
		return nil, fmt.Errorf("cannot acquire cache lock: %w", waitErr)
	}
	return func() {
		procReleaseMutex.Call(h)
		procCloseHandle.Call(h)
	}, nil
}

func replaceFile(src, dst string) error {
	ok, _, callErr := procMoveFileEx.Call(
		uintptr(unsafe.Pointer(utf16(src))),
		uintptr(unsafe.Pointer(utf16(dst))),
		moveReplace|moveThrough,
	)
	if ok == 0 {
		return fmt.Errorf("cannot activate %s: %w", filepath.Base(dst), callErr)
	}
	return nil
}

func writeAtomic(path string, data []byte) error {
	tmp := path + ".tmp-" + strconv.Itoa(os.Getpid())
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return err
	}
	if err := replaceFile(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func progressWindow(done <-chan error) error {
	procInitControls.Call()
	const ws = 0x00C00000 | 0x00080000 | 0x10000000
	h, _, _ := procCreateWindowEx.Call(0x00040000, uintptr(unsafe.Pointer(utf16("STATIC"))), uintptr(unsafe.Pointer(utf16("Preparing Nano Origin"))), ws, 0, 0, 390, 125, 0, 0, 0, 0)
	if h != 0 {
		procCreateWindowEx.Call(0, uintptr(unsafe.Pointer(utf16("STATIC"))), uintptr(unsafe.Pointer(utf16("Preparing Nano Origin for first launch…"))), 0x50000000, 24, 20, 335, 24, h, 0, 0, 0)
		bar, _, _ := procCreateWindowEx.Call(0, uintptr(unsafe.Pointer(utf16("msctls_progress32"))), 0, 0x50000008, 24, 58, 335, 18, h, 0, 0, 0)
		if bar != 0 {
			syscall.NewLazyDLL("user32.dll").NewProc("SendMessageW").Call(bar, 0x040A, 1, 50)
		}
		screenW, _, _ := procGetSystemMetrics.Call(0)
		screenH, _, _ := procGetSystemMetrics.Call(1)
		x, y := (int32(screenW)-390)/2, (int32(screenH)-125)/2
		procSetWindowPos.Call(h, 0, uintptr(x), uintptr(y), 390, 125, 0x0014)
		procShowWindow.Call(h, 5)
		procUpdateWindow.Call(h)
	}
	var m msg
	for {
		select {
		case err := <-done:
			if h != 0 {
				procDestroyWindow.Call(h)
			}
			return err
		default:
			for {
				r, _, _ := procPeekMessage.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0, pmRemove)
				if r == 0 {
					break
				}
				if m.Message == wmClose {
					return errors.New("preparation cancelled")
				}
				procTranslateMsg.Call(uintptr(unsafe.Pointer(&m)))
				procDispatchMsg.Call(uintptr(unsafe.Pointer(&m)))
			}
			time.Sleep(15 * time.Millisecond)
		}
	}
}

func readFooter(f *os.File) (footer, error) {
	var out footer
	info, err := f.Stat()
	if err != nil || info.Size() < footerSize {
		return out, errors.New("invalid Nano Origin bundle")
	}
	b := make([]byte, footerSize)
	if _, err = f.ReadAt(b, info.Size()-footerSize); err != nil {
		return out, err
	}
	if string(b[:16]) != magic {
		return out, errors.New("bundle footer is missing")
	}
	out.Bundle = strings.TrimRight(string(b[16:48]), "\x00")
	out.Offset = binary.LittleEndian.Uint64(b[48:56])
	out.Length = binary.LittleEndian.Uint64(b[56:64])
	copy(out.SHA[:], b[64:96])
	payloadEnd := uint64(info.Size() - footerSize)
	if out.Bundle == "" || out.Length == 0 || out.Offset > payloadEnd || out.Length > payloadEnd-out.Offset {
		return out, errors.New("bundle bounds are invalid")
	}
	return out, nil
}

func verifyPayload(f *os.File, ft footer) error {
	h := sha256.New()
	if _, err := io.Copy(h, io.NewSectionReader(f, int64(ft.Offset), int64(ft.Length))); err != nil {
		return err
	}
	if !bytes.Equal(h.Sum(nil), ft.SHA[:]) {
		return errors.New("embedded browser payload is corrupted")
	}
	return nil
}

func safeDestination(root, name string) (string, error) {
	if strings.ContainsAny(name, ":\x00") {
		return "", errors.New("invalid character in payload path")
	}
	if strings.HasPrefix(name, "/") || strings.HasPrefix(name, "\\") {
		return "", errors.New("rooted path in payload")
	}
	name = filepath.FromSlash(name)
	if filepath.IsAbs(name) || filepath.VolumeName(name) != "" {
		return "", errors.New("absolute path in payload")
	}
	clean := filepath.Clean(name)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
		return "", errors.New("unsafe path in payload")
	}
	dst := filepath.Join(root, clean)
	rel, err := filepath.Rel(root, dst)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return "", errors.New("payload path escapes staging directory")
	}
	return dst, nil
}

func extractPayload(exe *os.File, ft footer, stage string) error {
	zr, err := zip.NewReader(io.NewSectionReader(exe, int64(ft.Offset), int64(ft.Length)), int64(ft.Length))
	if err != nil {
		return err
	}
	var unpacked uint64
	for _, zf := range zr.File {
		dst, err := safeDestination(stage, zf.Name)
		if err != nil {
			return err
		}
		if zf.FileInfo().IsDir() {
			if err = os.MkdirAll(dst, 0755); err != nil {
				return err
			}
			continue
		}
		if zf.Mode()&os.ModeSymlink != 0 {
			return errors.New("symbolic link in payload")
		}
		if !zf.Mode().IsRegular() {
			return errors.New("non-regular file in payload")
		}
		if zf.UncompressedSize64 > maxUnpacked-unpacked {
			return errors.New("payload expands beyond the safety limit")
		}
		unpacked += zf.UncompressedSize64
		if err = os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
			return err
		}
		r, err := zf.Open()
		if err != nil {
			return err
		}
		w, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
		if err != nil {
			_ = r.Close()
			return err
		}
		_, err = io.Copy(w, r)
		closeErr := w.Close()
		readCloseErr := r.Close()
		if err != nil {
			return err
		}
		if closeErr != nil {
			return closeErr
		}
		if readCloseErr != nil {
			return readCloseErr
		}
	}
	return nil
}

func recoverCache(root string) error {
	runtime := filepath.Join(root, "runtime")
	old := filepath.Join(root, ".runtime-old")
	_, runtimeErr := os.Stat(runtime)
	_, oldErr := os.Stat(old)
	if runtimeErr != nil && !os.IsNotExist(runtimeErr) {
		return runtimeErr
	}
	if oldErr != nil && !os.IsNotExist(oldErr) {
		return oldErr
	}
	if os.IsNotExist(runtimeErr) && oldErr == nil {
		if err := os.Rename(old, runtime); err != nil {
			return fmt.Errorf("cannot recover previous runtime: %w", err)
		}
	} else if runtimeErr == nil && oldErr == nil {
		_ = os.RemoveAll(old)
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() && strings.HasPrefix(entry.Name(), ".staging-") {
			if err := os.RemoveAll(filepath.Join(root, entry.Name())); err != nil {
				return err
			}
		}
	}
	return nil
}

func prepare(exe *os.File, ft footer, root string) error {
	if err := recoverCache(root); err != nil {
		return err
	}
	stage := filepath.Join(root, ".staging-"+strconv.Itoa(os.Getpid()))
	if err := os.RemoveAll(stage); err != nil {
		return err
	}
	if err := os.MkdirAll(stage, 0755); err != nil {
		return err
	}
	defer os.RemoveAll(stage)
	if err := verifyPayload(exe, ft); err != nil {
		return err
	}
	if err := extractPayload(exe, ft, stage); err != nil {
		return err
	}
	if _, err := os.Stat(filepath.Join(stage, "runtime", "nano-origin-browser.exe")); err != nil {
		return errors.New("payload does not contain the browser runtime")
	}
	profile := filepath.Join(root, "profile")
	if _, err := os.Stat(profile); os.IsNotExist(err) {
		if err = os.Rename(filepath.Join(stage, "profile-seed"), profile); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	runtime, old := filepath.Join(root, "runtime"), filepath.Join(root, ".runtime-old")
	if err := os.RemoveAll(old); err != nil {
		return err
	}
	if _, err := os.Stat(runtime); err == nil {
		if err = os.Rename(runtime, old); err != nil {
			return err
		}
	}
	if err := os.Rename(filepath.Join(stage, "runtime"), runtime); err != nil {
		_ = os.Rename(old, runtime)
		return err
	}
	_ = os.RemoveAll(old)
	return writeAtomic(filepath.Join(root, "bundle-id"), []byte(ft.Bundle))
}

func run() error {
	path, err := os.Executable()
	if err != nil {
		return err
	}
	exe, err := os.Open(path)
	if err != nil {
		return err
	}
	defer exe.Close()
	ft, err := readFooter(exe)
	if err != nil {
		return err
	}
	local := os.Getenv("LOCALAPPDATA")
	if local == "" {
		return errors.New("LOCALAPPDATA is unavailable")
	}
	root := filepath.Join(local, "NanoOrigin")
	if err = os.MkdirAll(root, 0755); err != nil {
		return err
	}
	releaseLock, err := acquireCacheLock()
	if err != nil {
		return err
	}
	locked := true
	defer func() {
		if locked {
			releaseLock()
		}
	}()
	if err = recoverCache(root); err != nil {
		return err
	}
	installed, _ := os.ReadFile(filepath.Join(root, "bundle-id"))
	if string(installed) != ft.Bundle {
		done := make(chan error, 1)
		go func() { done <- prepare(exe, ft, root) }()
		if err = progressWindow(done); err != nil {
			return err
		}
	}
	releaseLock()
	locked = false
	browser := filepath.Join(root, "runtime", "nano-origin-browser.exe")
	profile := filepath.Join(root, "profile")
	cmd := exec.Command(browser, "-no-remote", "-profile", profile)
	cmd.Dir = filepath.Dir(browser)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	if err = cmd.Start(); err != nil {
		return err
	}
	time.Sleep(7 * time.Second)
	return nil
}

func main() {
	if err := run(); err != nil {
		messageBox(productName+" — Error", err.Error(), 0x10)
	}
}
