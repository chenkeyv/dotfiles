package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"
)

const (
	manifestPath        = ".dotfiles-bundle/manifest.json"
	toolsPrefix         = ".dotfiles-bundle/tools/"
	embeddedPayloadDir  = "payload"
	embeddedPayloadPath = "cmd/dotfiles/" + embeddedPayloadDir
)

type manifest struct {
	Version   int             `json:"version"`
	Mode      string          `json:"mode"`
	CreatedAt string          `json:"created_at"`
	GOOS      string          `json:"goos"`
	GOARCH    string          `json:"goarch"`
	Entries   []manifestEntry `json:"entries"`
	Tools     []string        `json:"tools"`
}

type manifestEntry struct {
	Path string `json:"path"`
	Type string `json:"type"`
	Mode uint32 `json:"mode"`
	Link string `json:"link,omitempty"`
}

type bundleOptions struct {
	mode     string
	baseDir  string
	toolsDir string
	inputs   []string
}

func main() {
	if err := run(os.Args); err != nil {
		fmt.Fprintf(os.Stderr, "dotfiles: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	applet, rest := resolveApplet(args)
	switch applet {
	case "help", "-h", "--help":
		mainUsage(os.Stdout)
		return nil
	case "pack":
		return packCommand(rest)
	case "list":
		return listCommand()
	case "extract":
		return extractCommand(rest)
	case "apply":
		return applyCommand(rest)
	case "tool":
		return toolCommand(rest)
	default:
		if hasPayload() {
			return runBundledTool(applet, rest)
		}
		mainUsage(os.Stderr)
		return fmt.Errorf("unknown applet: %s", applet)
	}
}

func resolveApplet(args []string) (string, []string) {
	name := "dotfiles"
	if len(args) > 0 {
		name = filepath.Base(args[0])
	}

	if isDirectApplet(name) {
		return name, args[1:]
	}

	if hasPayload() && isBundledToolName(name) {
		return name, args[1:]
	}

	if len(args) < 2 {
		return "help", nil
	}

	return args[1], args[2:]
}

func isDirectApplet(name string) bool {
	switch name {
	case "pack", "list", "extract", "apply", "tool", "help":
		return true
	default:
		return false
	}
}

func isBundledToolName(name string) bool {
	tools, err := bundledTools()
	if err != nil {
		return false
	}
	for _, tool := range tools {
		if tool == name {
			return true
		}
	}
	return false
}

func mainUsage(w io.Writer) {
	fmt.Fprintln(w, `Usage: dotfiles APPLET [ARGS...]
       APPLET [ARGS...]

Applets:
  pack     Write the payload directory used by embedded builds.
  list     List entries in the embedded payload.
  extract  Extract the embedded payload.
  apply    Apply a dotfiles environment bundle into a home directory.
  tool     List or run bundled tools.

Embedded bundles are multi-call binaries. They can also be symlinked as
extract, list, apply, or a bundled tool name.`)
}

func packCommand(args []string) error {
	fs := flag.NewFlagSet("pack", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	output := fs.String("o", "", "output payload directory")
	repo := fs.String("repo", ".", "dotfiles repo root")
	toolsDir := fs.String("tools-dir", "", "directory containing tool binaries or a bin subdirectory")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *output == "" {
		return errors.New("pack requires -o OUTPUT")
	}

	repoRoot, err := filepath.Abs(*repo)
	if err != nil {
		return err
	}

	inputs := dotfilesBundleInputs(repoRoot)
	if len(inputs) == 0 {
		return fmt.Errorf("no bundle inputs found under %s", repoRoot)
	}

	if err := buildPayload(bundleOptions{
		mode:     "dotfiles",
		baseDir:  repoRoot,
		toolsDir: *toolsDir,
		inputs:   inputs,
	}, *output); err != nil {
		return err
	}
	return nil
}

func dotfilesBundleInputs(repoRoot string) []string {
	return existingPaths(repoRoot, []string{
		"nvim",
		"zsh",
		"starship",
		"cmd",
		"setup.sh",
		"README.md",
		"AGENTS.md",
		"Makefile",
	})
}

func buildPayload(opts bundleOptions, output string) error {
	m := manifest{
		Version:   1,
		Mode:      opts.mode,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
		GOOS:      runtime.GOOS,
		GOARCH:    runtime.GOARCH,
	}

	tmp := output + ".tmp"
	if err := os.RemoveAll(tmp); err != nil {
		return err
	}
	if err := os.MkdirAll(tmp, 0o755); err != nil {
		return err
	}

	for _, input := range opts.inputs {
		if err := addPath(tmp, opts.baseDir, input, &m.Entries); err != nil {
			_ = os.RemoveAll(tmp)
			return err
		}
	}

	if opts.toolsDir != "" {
		if err := addTools(tmp, opts.toolsDir, &m.Tools, &m.Entries); err != nil {
			_ = os.RemoveAll(tmp)
			return err
		}
	}

	sort.Slice(m.Entries, func(i, j int) bool {
		return m.Entries[i].Path < m.Entries[j].Path
	})
	sort.Strings(m.Tools)
	if err := writeManifest(tmp, m); err != nil {
		_ = os.RemoveAll(tmp)
		return err
	}

	if err := os.RemoveAll(output); err != nil {
		_ = os.RemoveAll(tmp)
		return err
	}
	return os.Rename(tmp, output)
}

func validateInputs(baseDir string, inputs []string) error {
	for _, input := range inputs {
		if !safeInputPath(input) {
			return fmt.Errorf("unsafe input path: %s", input)
		}
		source := filepath.Join(baseDir, filepath.FromSlash(input))
		if _, err := os.Lstat(source); err != nil {
			return err
		}
	}
	return nil
}

func safeInputPath(name string) bool {
	if name == "" || filepath.IsAbs(name) {
		return false
	}
	clean := path.Clean(filepath.ToSlash(name))
	return clean != "." && clean != ".." && !strings.HasPrefix(clean, "../")
}

func existingPaths(base string, names []string) []string {
	var out []string
	for _, name := range names {
		if _, err := os.Lstat(filepath.Join(base, filepath.FromSlash(name))); err == nil {
			out = append(out, name)
		}
	}
	return out
}

func addPath(output, baseDir, input string, entries *[]manifestEntry) error {
	source := filepath.Join(baseDir, filepath.FromSlash(input))
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}

	if !info.IsDir() {
		archiveName := path.Clean(filepath.ToSlash(input))
		if skipArchiveName(archiveName) {
			return nil
		}
		return addOne(output, source, archiveName, info, entries)
	}

	return filepath.WalkDir(source, func(current string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(baseDir, current)
		if err != nil {
			return err
		}
		archiveName := path.Clean(filepath.ToSlash(rel))
		if skipArchiveName(archiveName) {
			return nil
		}
		return addOne(output, current, archiveName, info, entries)
	})
}

func skipArchiveName(name string) bool {
	tmpPayloadPath := embeddedPayloadPath + ".tmp"
	return name == embeddedPayloadPath ||
		strings.HasPrefix(name, embeddedPayloadPath+"/") ||
		name == tmpPayloadPath ||
		strings.HasPrefix(name, tmpPayloadPath+"/")
}

func addOne(output, source, archiveName string, info fs.FileInfo, entries *[]manifestEntry) error {
	if !safeArchiveName(archiveName) {
		return fmt.Errorf("unsafe archive path: %s", archiveName)
	}

	entry := manifestEntry{
		Path: archiveName,
		Mode: uint32(info.Mode().Perm()),
	}

	switch {
	case info.IsDir():
		entry.Type = "dir"
		*entries = append(*entries, entry)
		return os.MkdirAll(filepath.Join(output, filepath.FromSlash(archiveName)), info.Mode().Perm())
	case info.Mode()&os.ModeSymlink != 0:
		target, err := os.Readlink(source)
		if err != nil {
			return err
		}
		entry.Type = "symlink"
		entry.Link = target
		*entries = append(*entries, entry)
		return nil
	case info.Mode().IsRegular():
		entry.Type = "file"
		*entries = append(*entries, entry)
		return copyFile(source, filepath.Join(output, filepath.FromSlash(archiveName)), info.Mode().Perm())
	default:
		return nil
	}
}

func addTools(output, toolsDir string, tools *[]string, entries *[]manifestEntry) error {
	return filepath.WalkDir(toolsDir, func(current string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(toolsDir, current)
		if err != nil {
			return err
		}
		name := path.Clean(filepath.ToSlash(rel))
		if name == "." {
			return nil
		}
		archiveName := toolsPrefix + name
		if err := addOne(output, current, archiveName, info, entries); err != nil {
			return err
		}
		if strings.HasPrefix(name, "bin/") && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0 {
			*tools = append(*tools, strings.TrimPrefix(name, "bin/"))
		}
		return nil
	})
}

func writeManifest(output string, m manifest) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	dest := filepath.Join(output, filepath.FromSlash(manifestPath))
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	return os.WriteFile(dest, data, 0o644)
}

func safeArchiveName(name string) bool {
	if name == "" || strings.HasPrefix(name, "/") {
		return false
	}
	clean := path.Clean(name)
	return clean != "." && clean != ".." && !strings.HasPrefix(clean, "../")
}

func payloadFS() (fs.FS, error) {
	payloadFS := embeddedPayloadFS()
	if payloadFS == nil {
		return nil, errors.New("this executable was built without an embedded payload")
	}
	return payloadFS, nil
}

func payloadManifestBytes() ([]byte, error) {
	payloadFS, err := payloadFS()
	if err != nil {
		return nil, err
	}
	return fs.ReadFile(payloadFS, manifestPath)
}

func payloadManifest() (manifest, error) {
	data, err := payloadManifestBytes()
	if err != nil {
		return manifest{}, fmt.Errorf("read embedded manifest: %w", err)
	}
	var m manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return manifest{}, fmt.Errorf("parse embedded manifest: %w", err)
	}
	return m, nil
}

func hasPayload() bool {
	payloadFS := embeddedPayloadFS()
	if payloadFS == nil {
		return false
	}
	info, err := fs.Stat(payloadFS, manifestPath)
	return err == nil && info.Size() > 0
}

func listCommand() error {
	m, err := payloadManifest()
	if err != nil {
		return err
	}
	for _, entry := range m.Entries {
		fmt.Println(entry.Path)
	}
	return nil
}

func extractCommand(args []string) error {
	fs := flag.NewFlagSet("extract", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	target := fs.String("target", ".", "target directory")
	if err := fs.Parse(args); err != nil {
		return err
	}
	return extractPayloadTo(*target)
}

func extractPayloadTo(target string) error {
	payloadFS, err := payloadFS()
	if err != nil {
		return err
	}
	m, err := payloadManifest()
	if err != nil {
		return err
	}
	for _, entry := range m.Entries {
		if err := writePayloadEntry(payloadFS, target, entry); err != nil {
			return err
		}
	}
	return nil
}

func writePayloadEntry(payloadFS fs.FS, target string, entry manifestEntry) error {
	return writePayloadEntryAt(payloadFS, target, entry.Path, entry.Path, entry)
}

func writePayloadEntryAt(payloadFS fs.FS, target, sourcePath, destPath string, entry manifestEntry) error {
	if !safeArchiveName(sourcePath) {
		return fmt.Errorf("unsafe payload path: %s", sourcePath)
	}
	if !safeArchiveName(destPath) {
		return fmt.Errorf("unsafe output path: %s", destPath)
	}

	dest := filepath.Join(target, filepath.FromSlash(destPath))
	cleanTarget, err := filepath.Abs(target)
	if err != nil {
		return err
	}
	cleanDest, err := filepath.Abs(dest)
	if err != nil {
		return err
	}
	if cleanDest != cleanTarget && !strings.HasPrefix(cleanDest, cleanTarget+string(os.PathSeparator)) {
		return fmt.Errorf("payload path escapes target: %s", destPath)
	}

	mode := fs.FileMode(entry.Mode)
	switch entry.Type {
	case "dir":
		return os.MkdirAll(dest, mode)
	case "file":
		data, err := fs.ReadFile(payloadFS, sourcePath)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(dest, data, mode); err != nil {
			return err
		}
		return os.Chmod(dest, mode)
	case "symlink":
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}
		_ = os.Remove(dest)
		return os.Symlink(entry.Link, dest)
	default:
		return nil
	}
}

func applyCommand(args []string) error {
	fs := flag.NewFlagSet("apply", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	homeFlag := fs.String("home", "", "home directory to apply into")
	force := fs.Bool("force", false, "replace existing files without making backups")
	if err := fs.Parse(args); err != nil {
		return err
	}

	home := *homeFlag
	if home == "" {
		var err error
		home, err = os.UserHomeDir()
		if err != nil {
			return err
		}
	}
	home, err := filepath.Abs(home)
	if err != nil {
		return err
	}

	temp, err := os.MkdirTemp("", "dotfiles-bundle-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temp)

	if err := extractPayloadTo(temp); err != nil {
		return err
	}

	configHome := filepath.Join(home, ".config")
	if *homeFlag == "" {
		if env := os.Getenv("XDG_CONFIG_HOME"); env != "" {
			configHome = env
		}
	}
	localBin := filepath.Join(home, ".local", "bin")
	backupRoot := filepath.Join(configHome, "dotfiles-bundle-backups", time.Now().UTC().Format("20060102150405"))

	inst := installer{force: *force, backupRoot: backupRoot}
	rules := []installRule{
		{src: filepath.Join(temp, "nvim"), dst: filepath.Join(configHome, "nvim")},
		{src: filepath.Join(temp, "starship", "starship.toml"), dst: filepath.Join(configHome, "starship.toml")},
		{src: filepath.Join(temp, "zsh", "zshenv"), dst: filepath.Join(home, ".zshenv")},
		{src: filepath.Join(temp, "zsh", "zprofile"), dst: filepath.Join(home, ".zprofile")},
		{src: filepath.Join(temp, "zsh", "zshrc"), dst: filepath.Join(home, ".zshrc")},
		{src: filepath.Join(temp, "zsh", "zshenv"), dst: filepath.Join(configHome, "zsh", ".zshenv")},
		{src: filepath.Join(temp, "zsh", "zprofile"), dst: filepath.Join(configHome, "zsh", ".zprofile")},
		{src: filepath.Join(temp, "zsh", "zshrc"), dst: filepath.Join(configHome, "zsh", ".zshrc")},
		{src: filepath.Join(temp, "zsh", "plugins.txt"), dst: filepath.Join(configHome, "zsh", "plugins.txt")},
		{src: filepath.Join(temp, "zsh", "plugins-late.txt"), dst: filepath.Join(configHome, "zsh", "plugins-late.txt")},
	}

	for _, rule := range rules {
		if _, err := os.Lstat(rule.src); err == nil {
			if err := inst.install(rule.src, rule.dst); err != nil {
				return err
			}
		}
	}

	if err := os.MkdirAll(localBin, 0o755); err != nil {
		return err
	}

	toolsRoot := filepath.Join(temp, filepath.FromSlash(toolsPrefix))
	if info, err := os.Stat(toolsRoot); err == nil && info.IsDir() {
		if err := copyDirContents(toolsRoot, filepath.Join(home, ".local"), inst); err != nil {
			return err
		}
	}

	exe, err := os.Executable()
	if err != nil {
		return err
	}
	dotfilesTarget := filepath.Join(localBin, "dotfiles")
	if err := inst.install(exe, dotfilesTarget); err != nil {
		return err
	}

	fmt.Printf("Applied bundle into %s\n", home)
	fmt.Printf("Ensure %s is on PATH.\n", localBin)
	return nil
}

type installRule struct {
	src string
	dst string
}

type installer struct {
	force      bool
	backupRoot string
}

func (i installer) install(src, dst string) error {
	info, err := os.Lstat(src)
	if err != nil {
		return err
	}
	if err := i.prepare(dst); err != nil {
		return err
	}
	if info.IsDir() {
		return copyDir(src, dst)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		link, err := os.Readlink(src)
		if err != nil {
			return err
		}
		_ = os.Remove(dst)
		return os.Symlink(link, dst)
	}
	return copyFile(src, dst, info.Mode().Perm())
}

func (i installer) prepare(dst string) error {
	if _, err := os.Lstat(dst); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return os.MkdirAll(filepath.Dir(dst), 0o755)
		}
		return err
	}
	if i.force {
		return os.RemoveAll(dst)
	}
	rel := strings.TrimPrefix(dst, string(os.PathSeparator))
	backup := filepath.Join(i.backupRoot, rel)
	if err := os.MkdirAll(filepath.Dir(backup), 0o755); err != nil {
		return err
	}
	return os.Rename(dst, backup)
}

func copyDirContents(src, dst string, inst installer) error {
	return filepath.WalkDir(src, func(current string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(src, current)
		if err != nil {
			return err
		}
		return inst.install(current, filepath.Join(dst, rel))
	})
}

func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(current string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, current)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, info.Mode().Perm())
		}
		if info.Mode()&os.ModeSymlink != 0 {
			link, err := os.Readlink(current)
			if err != nil {
				return err
			}
			_ = os.Remove(target)
			return os.Symlink(link, target)
		}
		return copyFile(current, target, info.Mode().Perm())
	})
}

func copyFile(src, dst string, mode fs.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		_ = out.Close()
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	return os.Chmod(dst, mode)
}

func toolCommand(args []string) error {
	if len(args) == 0 || args[0] == "list" {
		tools, err := bundledTools()
		if err != nil {
			return err
		}
		for _, tool := range tools {
			fmt.Println(tool)
		}
		return nil
	}
	if args[0] == "run" {
		if len(args) < 2 {
			return errors.New("tool run requires NAME")
		}
		return runBundledTool(args[1], args[2:])
	}
	return runBundledTool(args[0], args[1:])
}

func bundledTools() ([]string, error) {
	m, err := payloadManifest()
	if err != nil {
		return nil, err
	}
	tools := append([]string(nil), m.Tools...)
	sort.Strings(tools)
	return tools, nil
}

func runBundledTool(name string, args []string) error {
	if !safeArchiveName(name) || strings.Contains(name, "/") {
		return fmt.Errorf("unsafe tool name: %s", name)
	}
	tools, err := bundledTools()
	if err != nil {
		return err
	}
	found := false
	for _, tool := range tools {
		if tool == name {
			found = true
			break
		}
	}
	if !found {
		return fmt.Errorf("bundle does not contain tool: %s", name)
	}
	manifestData, err := payloadManifestBytes()
	if err != nil {
		return err
	}
	sum := sha256.Sum256(manifestData)
	cacheRoot := filepath.Join(cacheHome(), "dotfiles-bundle", hex.EncodeToString(sum[:8]))
	toolPath := filepath.Join(cacheRoot, "bin", name)
	if _, err := os.Stat(toolPath); err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if err := extractToolTree(cacheRoot); err != nil {
			tempRoot, tempErr := os.MkdirTemp("", "dotfiles-tool-*")
			if tempErr != nil {
				return fmt.Errorf("extract bundled tool to cache: %w", err)
			}
			defer os.RemoveAll(tempRoot)
			cacheRoot = tempRoot
			toolPath = filepath.Join(cacheRoot, "bin", name)
			if tempErr := extractToolTree(cacheRoot); tempErr != nil {
				return fmt.Errorf("extract bundled tool to cache: %w; extract to temp: %w", err, tempErr)
			}
		}
	}

	cmd := exec.Command(toolPath, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	return cmd.Run()
}

func extractToolTree(target string) error {
	payloadFS, err := payloadFS()
	if err != nil {
		return err
	}
	m, err := payloadManifest()
	if err != nil {
		return err
	}
	found := false
	for _, entry := range m.Entries {
		if !strings.HasPrefix(entry.Path, toolsPrefix) {
			continue
		}
		found = true
		stripped := strings.TrimPrefix(entry.Path, toolsPrefix)
		if stripped == "" {
			continue
		}
		toolEntry := entry
		toolEntry.Path = stripped
		if err := writePayloadEntryAt(payloadFS, target, entry.Path, stripped, toolEntry); err != nil {
			return err
		}
	}
	if !found {
		return errors.New("bundle does not contain tools")
	}
	return nil
}

func cacheHome() string {
	if env := os.Getenv("XDG_CACHE_HOME"); env != "" {
		return env
	}
	home, err := os.UserHomeDir()
	if err == nil {
		return filepath.Join(home, ".cache")
	}
	return os.TempDir()
}
