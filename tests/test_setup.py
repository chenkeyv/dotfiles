from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "setup.sh"
MARKETPLACE_HELPER = ROOT / "scripts" / "ensure-personal-codex-marketplace.py"
AGENT_TOOLBOX_URL = "https://github.com/chenkeyv/agent-toolbox.git"


class SetupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.temp_path = Path(self.temp_dir.name)
        self.home = self.temp_path / "home"
        self.home.mkdir()

    def write_packages(
        self,
        *,
        plugins: list[str] | None = None,
        skills: list[object] | None = None,
    ) -> Path:
        path = self.temp_path / "codex-packages.json"
        path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "plugins": plugins or [],
                    "skills": skills or [],
                }
            ),
            encoding="utf-8",
        )
        return path

    def write_executable(self, directory: Path, name: str, body: str) -> Path:
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / name
        path.write_text("#!/bin/sh\nset -eu\n" + body, encoding="utf-8")
        path.chmod(0o755)
        return path

    def run_setup(
        self,
        packages: Path,
        *,
        skip_skills: bool = False,
        skip_plugins: bool = False,
        skip_font: bool = True,
        skip_node: bool = True,
        skip_editor_tools: bool = True,
        skip_skillhub: bool = True,
        dry_run: bool = True,
        force: bool = False,
        env_updates: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        args = [
            "/bin/bash",
            str(SETUP),
            "--skip-neovim-install",
            "--skip-zsh-install",
            "--skip-python-install",
            "--packages-file",
            str(packages),
        ]
        if skip_node:
            args.append("--skip-node-install")
        if skip_editor_tools:
            args.append("--skip-editor-tools-install")
        if skip_skillhub:
            args.append("--skip-skillhub-install")
        if dry_run:
            args.append("--dry-run")
        if force:
            args.append("--force")
        if skip_skills:
            args.append("--skip-skill-install")
        if skip_plugins:
            args.append("--skip-plugin-install")
        if skip_font:
            args.append("--skip-font-install")

        env = os.environ.copy()
        env.update(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.home / ".config"),
                "CODEX_HOME": str(self.home / ".codex"),
            }
        )
        if env_updates:
            env.update(env_updates)

        return subprocess.run(
            args,
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

    def isolated_path(self) -> Path:
        """Return a PATH directory hiding the developer tools on this machine."""
        directory = self.temp_path / "isolated-bin"
        directory.mkdir(exist_ok=True)
        for command in ("date", "dirname", "readlink", "sed"):
            source = shutil.which(command)
            self.assertIsNotNone(source)
            link = directory / command
            if not link.exists():
                link.symlink_to(source)
        python = directory / "python3"
        if not python.exists():
            python.symlink_to(sys.executable)
        self.write_executable(directory, "uname", "echo Darwin\n")
        self.write_executable(directory, "brew", "exit 0\n")
        return directory

    def test_only_missing_tools_are_installed(self) -> None:
        directory = self.isolated_path()
        self.write_executable(directory, "node", "exit 0\n")
        packages = self.write_packages()

        result = self.run_setup(
            packages,
            skip_skills=True,
            skip_plugins=True,
            skip_node=False,
            env_updates={"PATH": str(directory)},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("brew install pnpm\n", result.stdout)
        self.assertNotIn("brew install node", result.stdout)

        self.write_executable(directory, "pnpm", "exit 0\n")
        repeated = self.run_setup(
            packages,
            skip_skills=True,
            skip_plugins=True,
            skip_node=False,
            env_updates={"PATH": str(directory)},
        )

        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertIn("Node.js and pnpm already installed.", repeated.stdout)
        self.assertNotIn("brew install", repeated.stdout)

    def test_editor_tools_install_each_package_once(self) -> None:
        result = self.run_setup(
            self.write_packages(),
            skip_skills=True,
            skip_plugins=True,
            skip_editor_tools=False,
            env_updates={"PATH": str(self.isolated_path())},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        install = next(
            line for line in result.stdout.splitlines() if "brew install " in line
        )
        packages = install.split("brew install ", 1)[1].split()
        self.assertEqual(len(packages), len(set(packages)), install)
        for package in (
            "tree-sitter-cli",
            "vscode-langservers-extracted",
            "gopls",
            "typescript",
            "stylua",
        ):
            self.assertIn(package, packages)

    def test_skillhub_is_fetched_only_when_a_skill_needs_it(self) -> None:
        env_updates = {"PATH": str(self.isolated_path())}

        unused = self.run_setup(
            self.write_packages(skills=[{"name": "surge", "installer": "app"}]),
            skip_plugins=True,
            skip_skillhub=False,
            env_updates=env_updates,
        )
        self.assertEqual(unused.returncode, 0, unused.stderr)
        self.assertNotIn("install.sh", unused.stdout)

        needed = self.run_setup(
            self.write_packages(skills=[{"name": "demo", "installer": "skillhub"}]),
            skip_plugins=True,
            skip_skillhub=False,
            env_updates=env_updates,
        )
        self.assertEqual(needed.returncode, 0, needed.stderr)
        self.assertIn("install.sh", needed.stdout)
        self.assertIn("install demo --dir", needed.stdout)

        refused = self.run_setup(
            self.write_packages(skills=[{"name": "demo", "installer": "skillhub"}]),
            skip_plugins=True,
            env_updates=env_updates,
        )
        self.assertEqual(refused.returncode, 1, refused.stdout)
        self.assertIn("SkillHub CLI is required", refused.stderr)

    def test_missing_codex_skips_plugins_with_a_warning(self) -> None:
        result = self.run_setup(
            self.write_packages(plugins=["example@personal"]),
            skip_skills=True,
            dry_run=False,
            force=True,
            env_updates={"PATH": f"{self.isolated_path()}:/bin:/usr/bin"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Codex CLI not found; skipping 1 configured plugins.", result.stdout)
        self.assertIn("Dotfiles installed.", result.stdout)

    def test_plugin_failure_tries_the_rest_and_reads_the_list_once(self) -> None:
        fake_bin = self.temp_path / "bin"
        calls = self.temp_path / "codex-calls"
        self.write_executable(
            fake_bin,
            "codex",
            f'echo "$*" >> "{calls}"\n'
            'if [ "$1 $2" = "plugin list" ]; then\n'
            "  printf '%s\\n' '{\"installed\":[{\"pluginId\":\"done@market\",\"installed\":true,\"enabled\":true}]}'\n"
            "  exit 0\n"
            "fi\n"
            'case "$3" in\n'
            "  bad@market) echo 'not found' >&2; exit 23 ;;\n"
            "esac\n",
        )

        result = self.run_setup(
            self.write_packages(plugins=["done@market", "bad@market", "good@market"]),
            skip_skills=True,
            dry_run=False,
            force=True,
            env_updates={"PATH": f"{fake_bin}:{os.environ['PATH']}"},
        )

        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertIn("Failed to install Codex plugin bad@market", result.stderr)
        self.assertEqual(
            calls.read_text(encoding="utf-8").splitlines(),
            ["plugin list --json", "plugin add bad@market", "plugin add good@market"],
        )
        self.assertIn(
            "Codex plugin already installed and enabled: done@market", result.stdout
        )

    def test_personal_plugins_get_a_marketplace_entry(self) -> None:
        fake_bin = self.fake_codex("other@personal")
        marketplace = self.home / ".agents" / "plugins" / "marketplace.json"

        result = self.run_setup(
            self.write_packages(plugins=["task-skills@personal", "agent-toolbox@personal"]),
            skip_skills=True,
            dry_run=False,
            force=True,
            env_updates={"PATH": f"{fake_bin}:{os.environ['PATH']}"},
        )

        # The fake codex refuses `plugin add`; the entries come first regardless.
        self.assertEqual(result.returncode, 1, result.stderr)
        data = json.loads(marketplace.read_text(encoding="utf-8"))
        self.assertEqual(
            {entry["name"]: entry["source"]["url"] for entry in data["plugins"]},
            {
                "task-skills": "https://github.com/chenkeyv/task-skills.git",
                "agent-toolbox": AGENT_TOOLBOX_URL,
            },
        )

    def test_setup_retires_home_zsh_links_but_keeps_real_files(self) -> None:
        (self.home / ".zprofile").symlink_to(ROOT / "zsh" / "zprofile")
        (self.home / ".zshrc").write_text("# Mine\n", encoding="utf-8")

        result = self.run_setup(
            self.write_packages(),
            skip_skills=True,
            skip_plugins=True,
            dry_run=False,
            force=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / ".zprofile").is_symlink())
        self.assertEqual((self.home / ".zshrc").read_text(encoding="utf-8"), "# Mine\n")
        self.assertIn(f"Note: zsh ignores {self.home / '.zshrc'}", result.stdout)

    def test_zsh_configs_survive_plugin_failure_and_rerun(self) -> None:
        config_home = self.temp_path / "custom config"
        zsh_dir = config_home / "zsh"
        zsh_dir.mkdir(parents=True)
        local_config = zsh_dir / "local.zsh"
        local_config.write_text("export LOCAL_SETTING=preserved\n", encoding="utf-8")
        original_env = "# Existing Zsh environment\n"
        (self.home / ".zshenv").write_text(original_env, encoding="utf-8")
        fake_bin = self.temp_path / "bin"
        self.write_executable(
            fake_bin,
            "codex",
            'if [ "$1 $2" = "plugin list" ]; then\n'
            '  printf \'%s\\n\' \'{"installed":[]}\'\n'
            "  exit 0\n"
            "fi\n"
            "echo 'Simulated plugin installation failure' >&2\n"
            "exit 23\n",
        )
        packages = self.write_packages(plugins=["example@personal"])
        env = {
            "XDG_CONFIG_HOME": str(config_home),
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
        }

        failed = self.run_setup(
            packages, dry_run=False, force=True, skip_skills=True, env_updates=env
        )

        self.assertEqual(failed.returncode, 23, failed.stderr)
        self.assertIn("Simulated plugin installation failure", failed.stderr)
        self.assertIn("exec zsh -l", failed.stdout)
        self.assertNotIn("Dotfiles installed.", failed.stdout)
        for target, name in (
            (self.home / ".zshenv", "zshenv"),
            (zsh_dir / ".zshenv", "zshenv"),
            (zsh_dir / ".zprofile", "zprofile"),
            (zsh_dir / ".zshrc", "zshrc"),
        ):
            self.assertTrue(target.is_symlink(), str(target))
            self.assertEqual(target.resolve(), ROOT / "zsh" / name)
        for name in ("plugins.txt", "plugins-late.txt"):
            self.assertEqual((zsh_dir / name).resolve(), ROOT / "zsh" / name)
        self.assertEqual(
            (config_home / "starship.toml").resolve(), ROOT / "starship" / "starship.toml"
        )
        backups = list((config_home / "dotfiles-backups").glob("zshenv.2*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(encoding="utf-8"), original_env)

        repeated = self.run_setup(
            packages, dry_run=False, skip_skills=True, skip_plugins=True, env_updates=env
        )

        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertIn("Dotfiles installed.", repeated.stdout)
        self.assertEqual(
            list((config_home / "dotfiles-backups").glob("zshenv.2*")), backups
        )
        self.assertEqual(
            local_config.read_text(encoding="utf-8"), "export LOCAL_SETTING=preserved\n"
        )

    def test_ghostty_config_backup_dry_run_and_idempotency(self) -> None:
        config_home = self.temp_path / "custom config"
        target = config_home / "ghostty" / "config"
        target.parent.mkdir(parents=True)
        original = "font-size = 12\n"
        target.write_text(original, encoding="utf-8")
        sibling = target.parent / "local-theme"
        sibling.write_text("background = #112233\n", encoding="utf-8")
        packages = self.write_packages()
        options = {
            "skip_skills": True,
            "skip_plugins": True,
            "env_updates": {"XDG_CONFIG_HOME": str(config_home)},
        }

        preview = self.run_setup(packages, **options)
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertEqual(target.read_text(encoding="utf-8"), original)
        self.assertFalse(target.is_symlink())
        self.assertFalse((config_home / "dotfiles-backups").exists())

        installed = self.run_setup(packages, dry_run=False, force=True, **options)
        self.assertEqual(installed.returncode, 0, installed.stderr)
        self.assertTrue(target.is_symlink())
        self.assertEqual(target.resolve(), ROOT / "ghostty" / "config")
        backups = list((config_home / "dotfiles-backups").glob("ghostty-config.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(encoding="utf-8"), original)

        repeated = self.run_setup(packages, dry_run=False, **options)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertIn(f"Already linked: {target}", repeated.stdout)
        self.assertEqual(
            list((config_home / "dotfiles-backups").glob("ghostty-config.*")), backups
        )
        self.assertEqual(sibling.read_text(encoding="utf-8"), "background = #112233\n")
        self.assertFalse((self.home / ".config" / "ghostty").exists())

    def test_font_install_dry_run_skip_and_idempotency(self) -> None:
        fake_bin = self.temp_path / "bin"
        installed = self.temp_path / "font-installed"
        installs = self.temp_path / "font-installs"
        self.write_executable(fake_bin, "uname", 'echo "$FAKE_OS"\n')
        package_manager = (
            'case "$*" in\n'
            '  "list --cask --versions font-maple-mono-nf" | "-Q maplemono-nf-unhinted")\n'
            '    test -f "$FONT_INSTALLED" ;;\n'
            '  "install --cask font-maple-mono-nf" | "-S --needed --noconfirm maplemono-nf-unhinted")\n'
            '    touch "$FONT_INSTALLED"\n'
            '    echo installed >> "$FONT_INSTALLS" ;;\n'
            '  *) echo "Unexpected package command: $*" >&2; exit 99 ;;\n'
            "esac\n"
        )
        for command in ("brew", "pacman", "paru"):
            self.write_executable(fake_bin, command, package_manager)
        packages = self.write_packages()
        for platform in ("Darwin", "Linux"):
            with self.subTest(platform=platform):
                installed.unlink(missing_ok=True)
                installs.unlink(missing_ok=True)
                options = {
                    "skip_skills": True,
                    "skip_plugins": True,
                    "env_updates": {
                        "PATH": f"{fake_bin}:{os.environ['PATH']}",
                        "FAKE_OS": platform,
                        "FONT_INSTALLED": str(installed),
                        "FONT_INSTALLS": str(installs),
                    },
                }

                skipped = self.run_setup(packages, dry_run=False, **options)
                self.assertEqual(skipped.returncode, 0, skipped.stderr)
                self.assertFalse(installed.exists())

                preview = self.run_setup(packages, skip_font=False, **options)
                self.assertEqual(preview.returncode, 0, preview.stderr)
                self.assertTrue(
                    "brew install --cask font-maple-mono-nf" in preview.stdout
                    or "paru -S --needed --noconfirm maplemono-nf-unhinted" in preview.stdout,
                    preview.stdout,
                )
                self.assertFalse(installed.exists())

                first = self.run_setup(
                    packages, skip_font=False, dry_run=False, **options
                )
                self.assertEqual(first.returncode, 0, first.stderr)
                self.assertTrue(installed.exists())

                repeated = self.run_setup(
                    packages, skip_font=False, dry_run=False, **options
                )
                self.assertEqual(repeated.returncode, 0, repeated.stderr)
                self.assertIn("Maple Mono NF is already installed.", repeated.stdout)
                self.assertEqual(installs.read_text(encoding="utf-8"), "installed\n")

    def configure_personal_marketplace(self) -> Path:
        marketplace = self.home / ".agents" / "plugins" / "marketplace.json"
        subprocess.run(
            [
                sys.executable,
                str(MARKETPLACE_HELPER),
                str(marketplace),
                AGENT_TOOLBOX_URL,
            ],
            check=True,
        )
        return marketplace

    def fake_codex(self, plugin_id: str) -> Path:
        fake_bin = self.temp_path / "bin"
        payload = json.dumps(
            {
                "installed": [
                    {
                        "pluginId": plugin_id,
                        "installed": True,
                        "enabled": True,
                    }
                ]
            }
        )
        self.write_executable(
            fake_bin,
            "codex",
            "if [ \"$1 $2 $3\" = \"plugin list --json\" ]; then\n"
            f"  printf '%s\\n' '{payload}'\n"
            "  exit 0\n"
            "fi\n"
            "exit 1\n",
        )
        return fake_bin

    def test_personal_marketplace_helper_preserves_other_plugins(self) -> None:
        marketplace = self.home / ".agents" / "plugins" / "marketplace.json"
        marketplace.parent.mkdir(parents=True)
        marketplace.write_text(
            json.dumps(
                {
                    "name": "personal",
                    "interface": {"displayName": "My Plugins"},
                    "plugins": [
                        {
                            "name": "other-plugin",
                            "source": "./plugins/other-plugin",
                            "policy": {
                                "installation": "AVAILABLE",
                                "authentication": "ON_USE",
                            },
                            "category": "Productivity",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

        subprocess.run(
            [
                sys.executable,
                str(MARKETPLACE_HELPER),
                str(marketplace),
                AGENT_TOOLBOX_URL,
            ],
            check=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(MARKETPLACE_HELPER),
                "--check",
                str(marketplace),
                AGENT_TOOLBOX_URL,
            ],
            check=True,
        )

        data = json.loads(marketplace.read_text(encoding="utf-8"))
        self.assertEqual(data["interface"]["displayName"], "My Plugins")
        self.assertEqual([entry["name"] for entry in data["plugins"]], [
            "other-plugin",
            "agent-toolbox",
        ])
        self.assertEqual(
            data["plugins"][1]["source"],
            {"source": "url", "url": AGENT_TOOLBOX_URL, "ref": "main"},
        )

    def test_plugin_detection_requires_the_full_selector(self) -> None:
        self.configure_personal_marketplace()
        fake_bin = self.fake_codex("agent-toolbox@other")
        packages = self.write_packages(plugins=["agent-toolbox@personal"])

        result = self.run_setup(
            packages,
            skip_skills=True,
            env_updates={"PATH": f"{fake_bin}:{os.environ['PATH']}"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("codex plugin add agent-toolbox@personal", result.stdout)

    def test_fresh_agent_toolbox_dry_run_plans_marketplace_without_writing(self) -> None:
        fake_bin = self.fake_codex("other-plugin@personal")
        packages = self.write_packages(plugins=["agent-toolbox@personal"])
        marketplace = self.home / ".agents" / "plugins" / "marketplace.json"

        result = self.run_setup(
            packages,
            skip_skills=True,
            env_updates={"PATH": f"{fake_bin}:{os.environ['PATH']}"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "Adding agent-toolbox to the personal Codex marketplace.",
            result.stdout,
        )
        self.assertIn("codex plugin add agent-toolbox@personal", result.stdout)
        self.assertFalse(marketplace.exists())

    def test_plugin_detection_skips_the_exact_selector(self) -> None:
        self.configure_personal_marketplace()
        fake_bin = self.fake_codex("agent-toolbox@personal")
        packages = self.write_packages(plugins=["agent-toolbox@personal"])

        result = self.run_setup(
            packages,
            skip_skills=True,
            env_updates={"PATH": f"{fake_bin}:{os.environ['PATH']}"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "Codex plugin already installed and enabled: agent-toolbox@personal",
            result.stdout,
        )
        self.assertNotIn("+ codex plugin add", result.stdout)

    def test_package_parser_uses_uv_managed_python_outside_path(self) -> None:
        fake_bin = self.temp_path / "pythonless-bin"
        for command in ("date", "dirname"):
            source = shutil.which(command)
            self.assertIsNotNone(source)
            (fake_bin / command).parent.mkdir(parents=True, exist_ok=True)
            (fake_bin / command).symlink_to(source)
        self.write_executable(
            fake_bin,
            "uv",
            "if [ \"$1 $2\" = \"python find\" ]; then\n"
            "  printf '%s\\n' \"$FAKE_PYTHON\"\n"
            "  exit 0\n"
            "fi\n"
            "exit 1\n",
        )
        packages = self.write_packages()

        result = self.run_setup(
            packages,
            skip_skills=True,
            env_updates={"PATH": str(fake_bin), "FAKE_PYTHON": sys.executable},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Python 3 is required", result.stderr)

    def test_surge_repairs_an_existing_wrong_directory(self) -> None:
        source = self.temp_path / "SurgeSkill"
        source.mkdir()
        (source / "SKILL.md").write_text("# Surge\n", encoding="utf-8")
        target = self.home / ".codex" / "skills" / "surge"
        target.mkdir(parents=True)
        (target / "SKILL.md").write_text("# Stale\n", encoding="utf-8")
        packages = self.write_packages(
            skills=[{"name": "surge", "installer": "app"}]
        )

        result = self.run_setup(
            packages,
            skip_plugins=True,
            env_updates={"DOTFILES_SURGE_SKILL_SOURCE": str(source)},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"mv {target}", result.stdout)
        self.assertIn(f"ln -s {source} {target}", result.stdout)


@unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
class ZshConfigTests(unittest.TestCase):
    FAKE_ANTIDOTE = """
antidote() {
  [[ "$1" == bundle ]] || return 0
  if [[ -n "${FAKE_ANTIDOTE_FAIL:-}" ]]; then
    print -u2 'fatal: simulated offline clone'
    return 1
  fi
  print 'typeset -g FAKE_PLUGIN_LOADED=1'
}
"""

    def setUp(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        self.home = Path(temp_dir.name).resolve()
        zsh_dir = self.home / ".config" / "zsh"
        zsh_dir.mkdir(parents=True)
        (self.home / ".zshenv").symlink_to(ROOT / "zsh" / "zshenv")
        (zsh_dir / ".zshenv").symlink_to(ROOT / "zsh" / "zshenv")
        (zsh_dir / ".zprofile").symlink_to(ROOT / "zsh" / "zprofile")
        (zsh_dir / ".zshrc").symlink_to(ROOT / "zsh" / "zshrc")
        (zsh_dir / "plugins.txt").write_text("owner/repo\n", encoding="utf-8")
        antidote = self.home / ".local" / "share" / "dotfiles" / "antidote"
        antidote.mkdir(parents=True)
        (antidote / "antidote.zsh").write_text(self.FAKE_ANTIDOTE, encoding="utf-8")
        self.bundle = self.home / ".cache" / "zsh" / "plugins.zsh"

    def zsh(
        self, flags: str, command: str, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [shutil.which("zsh"), flags, command],
            env={
                "HOME": str(self.home),
                "PATH": "/usr/bin:/bin",
                "TERM": "dumb",
                **(env or {}),
            },
            stdin=subprocess.DEVNULL,
            check=False,
            capture_output=True,
            text=True,
        )

    def plugin_loaded(self, env: dict[str, str] | None = None) -> str:
        result = self.zsh("-ic", "print -r -- @@${FAKE_PLUGIN_LOADED:-no}", env)
        return result.stdout.rsplit("@@", 1)[-1].strip()

    def test_failed_plugin_download_is_retried(self) -> None:
        offline = self.zsh("-ic", "true", {"FAKE_ANTIDOTE_FAIL": "1"})

        self.assertIn("could not update zsh plugins", offline.stderr)
        self.assertFalse(self.bundle.exists())
        self.assertEqual(self.plugin_loaded(), "1")

    def test_empty_bundle_from_an_older_failure_heals(self) -> None:
        self.bundle.parent.mkdir(parents=True)
        self.bundle.touch()
        future = self.bundle.stat().st_mtime + 60
        os.utime(self.bundle, (future, future))

        self.assertEqual(self.plugin_loaded(), "1")
        self.assertGreater(self.bundle.stat().st_size, 0)

    def test_failed_update_keeps_the_working_bundle(self) -> None:
        self.assertEqual(self.plugin_loaded(), "1")
        working = self.bundle.read_text(encoding="utf-8")
        past = self.bundle.stat().st_mtime - 60
        os.utime(self.bundle, (past, past))

        self.assertEqual(self.plugin_loaded({"FAKE_ANTIDOTE_FAIL": "1"}), "1")
        self.assertEqual(self.bundle.read_text(encoding="utf-8"), working)

    def user_path(self, flags: str, env: dict[str, str] | None = None) -> list[str]:
        result = self.zsh(flags, "print -r -- @@; print -rl -- $path", env)
        entries = result.stdout.rsplit("@@", 1)[-1].split()
        return [entry for entry in entries if entry.startswith(str(self.home))]

    def test_every_shell_type_resolves_the_same_user_tools(self) -> None:
        for directory in (".local/bin", "bin", ".cargo/bin", "go/bin"):
            (self.home / directory).mkdir(parents=True, exist_ok=True)
        expected = [
            str(self.home / directory)
            for directory in (".local/bin", "bin", ".cargo/bin", "go/bin")
        ]

        for flags in ("-lc", "-ic", "-lic"):
            with self.subTest(flags=flags):
                self.assertEqual(self.user_path(flags), expected)

    def test_nested_shell_keeps_the_callers_path_order(self) -> None:
        virtualenv = self.home / "venv" / "bin"
        virtualenv.mkdir(parents=True)
        (self.home / ".local" / "bin").mkdir(parents=True)

        entries = self.user_path(
            "-ic",
            {"PATH": f"{virtualenv}:/usr/bin:/bin", "DOTFILES_ZPROFILE_LOADED": "1"},
        )

        self.assertEqual(entries[0], str(virtualenv))

    def test_history_settings_do_not_reach_child_shells(self) -> None:
        result = self.zsh(
            "-ic",
            "print -r -- @@; /usr/bin/env | /usr/bin/grep -E '^(HISTFILE|HISTSIZE|SAVEHIST)=' || print none",
            {"HISTFILE": str(self.home / "from-parent"), "HISTSIZE": "1"},
        )

        self.assertEqual(result.stdout.rsplit("@@", 1)[-1].strip(), "none")

    def test_only_one_history_sharing_mode_is_enabled(self) -> None:
        result = self.zsh(
            "-ic",
            "print -r -- @@$options[share_history],$options[inc_append_history_time]",
        )

        self.assertEqual(result.stdout.rsplit("@@", 1)[-1].strip(), "on,off")

    def test_iterm_integration_loads_only_in_iterm(self) -> None:
        (self.home / ".iterm2_shell_integration.zsh").write_text(
            "typeset -g ITERM_LOADED=yes\n", encoding="utf-8"
        )
        command = "print -r -- @@${ITERM_LOADED:-no}"

        for terminal, expected in (("ghostty", "no"), ("iTerm.app", "yes")):
            with self.subTest(terminal=terminal):
                result = self.zsh("-ic", command, {"TERM_PROGRAM": terminal})
                self.assertEqual(result.stdout.rsplit("@@", 1)[-1].strip(), expected)


if __name__ == "__main__":
    unittest.main()
