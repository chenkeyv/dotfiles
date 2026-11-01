package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func writeTestFile(t *testing.T, path, content string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
}

func TestInstallSelfKeepsTheRunningBinary(t *testing.T) {
	for _, force := range []bool{false, true} {
		dir := t.TempDir()
		target := filepath.Join(dir, "bin", "dotfiles")
		writeTestFile(t, target, "binary", 0o755)
		inst := installer{force: force, backupRoot: filepath.Join(dir, "backups")}

		if err := installSelf(inst, target, target); err != nil {
			t.Fatalf("force=%v: %v", force, err)
		}

		content, err := os.ReadFile(target)
		if err != nil {
			t.Fatalf("force=%v: running binary was removed: %v", force, err)
		}
		if string(content) != "binary" {
			t.Fatalf("force=%v: content = %q", force, content)
		}
	}
}

func TestInstallSelfKeepsTheBinaryBehindASymlink(t *testing.T) {
	dir := t.TempDir()
	exe := filepath.Join(dir, "dotfiles-env")
	writeTestFile(t, exe, "binary", 0o755)
	target := filepath.Join(dir, "dotfiles")
	if err := os.Symlink(exe, target); err != nil {
		t.Fatal(err)
	}

	if err := installSelf(installer{force: true}, exe, target); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(target); err != nil {
		t.Fatalf("link was removed: %v", err)
	}
}

func TestInstallSelfUpdatesAnOlderCopy(t *testing.T) {
	dir := t.TempDir()
	exe := filepath.Join(dir, "new")
	target := filepath.Join(dir, "bin", "dotfiles")
	writeTestFile(t, exe, "new", 0o755)
	writeTestFile(t, target, "old", 0o755)

	inst := installer{backupRoot: filepath.Join(dir, "backups")}
	if err := installSelf(inst, exe, target); err != nil {
		t.Fatal(err)
	}

	content, err := os.ReadFile(target)
	if err != nil || string(content) != "new" {
		t.Fatalf("content = %q, err = %v", content, err)
	}
}

func TestToolExitErrorKeepsTheStatus(t *testing.T) {
	err := toolExitError(exec.Command("/bin/sh", "-c", "exit 3").Run())

	var exit exitCodeError
	if !errors.As(err, &exit) || exit.code != 3 {
		t.Fatalf("err = %v", err)
	}
}

func TestToolExitErrorMapsSignals(t *testing.T) {
	err := toolExitError(exec.Command("/bin/sh", "-c", "kill -TERM $$").Run())

	var exit exitCodeError
	if !errors.As(err, &exit) || exit.code != 128+15 {
		t.Fatalf("err = %v", err)
	}
}

func TestToolExitErrorPassesSuccessAndStartFailures(t *testing.T) {
	if err := toolExitError(nil); err != nil {
		t.Fatalf("err = %v", err)
	}

	err := toolExitError(exec.Command("/nonexistent/tool").Run())
	var exit exitCodeError
	if err == nil || errors.As(err, &exit) {
		t.Fatalf("a start failure must not look like a tool exit: %v", err)
	}
}

func TestDataArchiveRoundTrip(t *testing.T) {
	data := t.TempDir()
	site := filepath.Join(data, "nvim", "site")
	writeTestFile(t, filepath.Join(site, "pack", "core", "opt", "demo", "lua", "demo.lua"), "return 1\n", 0o644)
	writeTestFile(t, filepath.Join(site, "pack", "core", "opt", "demo", ".git", "HEAD"), "ref\n", 0o444)
	writeTestFile(t, filepath.Join(site, "parser", "lua.so"), "elf", 0o755)
	queries := filepath.Join(site, "pack", "core", "opt", "demo", "queries", "lua")
	writeTestFile(t, filepath.Join(queries, "highlights.scm"), "; q\n", 0o644)
	if err := os.MkdirAll(filepath.Join(site, "queries"), 0o755); err != nil {
		t.Fatal(err)
	}
	// nvim-treesitter links queries with absolute paths.
	if err := os.Symlink(queries, filepath.Join(site, "queries", "lua")); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(data, "nvim", "log"), "not part of the bundle", 0o644)

	archive := filepath.Join(t.TempDir(), "nested", "data.tar.gz")
	if err := writeDataArchive(data, archive); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(archive)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	dest := t.TempDir()
	if err := extractDataArchive(file, dest); err != nil {
		t.Fatal(err)
	}

	gitHead := filepath.Join(dest, "nvim", "site", "pack", "core", "opt", "demo", ".git", "HEAD")
	if content, err := os.ReadFile(gitHead); err != nil || string(content) != "ref\n" {
		t.Fatalf(".git must survive: %q, %v", content, err)
	}
	info, err := os.Stat(filepath.Join(dest, "nvim", "site", "parser", "lua.so"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o755 {
		t.Fatalf("parser mode = %v", info.Mode().Perm())
	}
	link := filepath.Join(dest, "nvim", "site", "queries", "lua")
	target, err := os.Readlink(link)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.IsAbs(target) {
		t.Fatalf("link still points at the build host: %s", target)
	}
	if _, err := os.ReadFile(filepath.Join(link, "highlights.scm")); err != nil {
		t.Fatalf("link does not resolve after moving hosts: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dest, "nvim", "log")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("only data units belong in the archive: %v", err)
	}
}

func TestWriteDataArchiveRejectsLinksOutsideTheData(t *testing.T) {
	data := t.TempDir()
	site := filepath.Join(data, "nvim", "site")
	if err := os.MkdirAll(site, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/etc/hosts", filepath.Join(site, "hosts")); err != nil {
		t.Fatal(err)
	}

	err := writeDataArchive(data, filepath.Join(t.TempDir(), "data.tar.gz"))
	if err == nil || !strings.Contains(err.Error(), "outside the data directory") {
		t.Fatalf("err = %v", err)
	}
}

func TestWriteDataArchiveFailsWithoutData(t *testing.T) {
	if err := writeDataArchive(t.TempDir(), filepath.Join(t.TempDir(), "data.tar.gz")); err == nil {
		t.Fatal("an empty data directory must not produce a bundle that looks complete")
	}
}

func dataArchiveWith(t *testing.T, header tar.Header, body string) *bytes.Reader {
	t.Helper()
	var buffer bytes.Buffer
	gz := gzip.NewWriter(&buffer)
	tw := tar.NewWriter(gz)
	header.Size = int64(len(body))
	if err := tw.WriteHeader(&header); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write([]byte(body)); err != nil {
		t.Fatal(err)
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return bytes.NewReader(buffer.Bytes())
}

func TestExtractDataArchiveRejectsEscapes(t *testing.T) {
	cases := map[string]tar.Header{
		"parent path":   {Name: "../evil", Typeflag: tar.TypeReg, Mode: 0o644},
		"absolute path": {Name: "/tmp/evil", Typeflag: tar.TypeReg, Mode: 0o644},
		"absolute link": {Name: "link", Typeflag: tar.TypeSymlink, Linkname: "/etc/passwd"},
		"escaping link": {Name: "a/link", Typeflag: tar.TypeSymlink, Linkname: "../../evil"},
	}
	for name, header := range cases {
		t.Run(name, func(t *testing.T) {
			if err := extractDataArchive(dataArchiveWith(t, header, ""), t.TempDir()); err == nil {
				t.Fatal("expected an error")
			}
		})
	}
}

func TestInstallBundledDataReplacesUnitsOncePerBuild(t *testing.T) {
	data := t.TempDir()
	writeTestFile(t, filepath.Join(data, "nvim", "site", "new-file"), "new", 0o644)
	writeTestFile(t, filepath.Join(data, "dotfiles", "antidote", "antidote.zsh"), "zsh", 0o644)

	payload := t.TempDir()
	archive := filepath.Join(payload, filepath.FromSlash(dataArchivePath))
	if err := writeDataArchive(data, archive); err != nil {
		t.Fatal(err)
	}

	dataHome := filepath.Join(t.TempDir(), "share")
	writeTestFile(t, filepath.Join(dataHome, "nvim", "site", "old-file"), "old", 0o644)
	writeTestFile(t, filepath.Join(dataHome, "unrelated"), "keep", 0o644)
	backups := t.TempDir()
	inst := installer{backupRoot: backups}

	if err := installBundledData(payload, dataHome, inst); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(filepath.Join(dataHome, "nvim", "site", "new-file")); err != nil {
		t.Fatalf("new data missing: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dataHome, "nvim", "site", "old-file")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("a unit must be replaced whole: %v", err)
	}
	if _, err := os.Stat(filepath.Join(backups, strings.TrimPrefix(dataHome, "/"), "nvim", "site", "old-file")); err != nil {
		t.Fatalf("old data must be backed up: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dataHome, "unrelated")); err != nil {
		t.Fatalf("unrelated data must stay: %v", err)
	}
	entries, err := os.ReadDir(dataHome)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".dotfiles-data-") {
			t.Fatalf("staging directory left behind: %s", entry.Name())
		}
	}

	// A second apply of the same build must not touch local changes.
	localChange := filepath.Join(dataHome, "nvim", "site", "local-change")
	writeTestFile(t, localChange, "local", 0o644)
	if err := installBundledData(payload, dataHome, inst); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(localChange); err != nil {
		t.Fatalf("rerun replaced current data: %v", err)
	}
}

func TestInstallBundledDataWithoutAnArchiveIsANoOp(t *testing.T) {
	dataHome := filepath.Join(t.TempDir(), "share")
	if err := installBundledData(t.TempDir(), dataHome, installer{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(dataHome); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("no archive means nothing to create: %v", err)
	}
}
