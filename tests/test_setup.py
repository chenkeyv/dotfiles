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
            "--skip-node-install",
            "--skip-skillhub-install",
            "--packages-file",
            str(packages),
        ]
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

    def test_zsh_configs_survive_plugin_failure_and_rerun(self) -> None:
        config_home = self.temp_path / "custom config"
        zsh_dir = config_home / "zsh"
        zsh_dir.mkdir(parents=True)
        local_config = zsh_dir / "local.zsh"
        local_config.write_text("export LOCAL_SETTING=preserved\n", encoding="utf-8")
        original_rc = "# Existing Zsh config\n"
        (self.home / ".zshrc").write_text(original_rc, encoding="utf-8")
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
        for name in ("zshenv", "zprofile", "zshrc"):
            for directory in (self.home, zsh_dir):
                target = directory / f".{name}"
                self.assertTrue(target.is_symlink(), str(target))
                self.assertEqual(target.resolve(), ROOT / "zsh" / name)
        for name in ("plugins.txt", "plugins-late.txt"):
            self.assertEqual((zsh_dir / name).resolve(), ROOT / "zsh" / name)
        self.assertEqual(
            (config_home / "starship.toml").resolve(), ROOT / "starship" / "starship.toml"
        )
        backups = list((config_home / "dotfiles-backups").glob("zshrc.home.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(encoding="utf-8"), original_rc)

        repeated = self.run_setup(
            packages, dry_run=False, skip_skills=True, skip_plugins=True, env_updates=env
        )

        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertIn("Dotfiles installed.", repeated.stdout)
        self.assertEqual(
            list((config_home / "dotfiles-backups").glob("zshrc.home.*")), backups
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
            "Configuring Agent Toolbox in the personal Codex marketplace.",
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


if __name__ == "__main__":
    unittest.main()
