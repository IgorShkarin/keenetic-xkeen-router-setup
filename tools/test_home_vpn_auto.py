"""Offline checks for failover, recovery and bounded incident retention."""
import gzip
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

TOOLS = Path(__file__).resolve().parent


class RouterFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "opt"
        self.tmp = Path(self.temp.name) / "tmp"
        self.tmp.mkdir()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        for path in ("sbin", "etc/xray/configs", "var/lib/home-vpn-auto", "var/lib/blanc-auto", "var/log/xray"):
            (self.root / path).mkdir(parents=True)
        self.state = self.root / "var/lib/home-vpn-auto"
        self.active = self.root / "etc/xray/configs/04_outbounds.json"
        self.active.write_text("home\n")
        (self.root / "etc/xray/home-vpn.json").write_text("home\n")
        (self.root / "etc/xray/home-vpn-probe.json").write_text("probe\n")
        (self.state / "fallback.json").write_text("fallback\n")
        (self.state / "mode").write_text("home\n")
        (self.state / "fails").write_text("0\n")
        for name in ("access", "error"):
            (self.root / f"var/log/xray/{name}.log").write_text("historical diagnostic evidence\n")
        for name in ("home-vpn-auto", "home-vpn-log"):
            path = self.root / "sbin" / name
            shutil.copyfile(TOOLS / f"{name}.sh", path)
            path.chmod(0o755)
        self.env = dict(os.environ, HOME_VPN_ROOT=str(self.root), HOME_VPN_TMP=str(self.tmp),
                        HOME_VPN_PATH=f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin", HOME_HEALTH="up", PROBE_HEALTH="up")
        self.mock("sleep", "#!/bin/sh\nexit 0\n")
        self.mock("sha256sum", f"#!{shutil.which('python3')}\nimport hashlib,sys\nfrom pathlib import Path\nprint(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest(),sys.argv[1])\n")
        self.mock("logger", "#!/bin/sh\nexit 0\n")
        self.mock_blanc = self.root / "sbin/blanc-auto"
        self.mock_blanc.write_text('#!/bin/sh\necho amnezia > "$HOME_VPN_ROOT/etc/xray/configs/04_outbounds.json"\necho recovered > "$HOME_VPN_ROOT/var/lib/home-vpn-auto/pool-recovery"\n')
        self.mock_blanc.chmod(0o755)
        self.mock("xkeen", "#!/bin/sh\necho restart >> \"$HOME_VPN_ROOT/var/lib/home-vpn-auto/restarts\"\nexit 0\n")
        self.mock("xray", f"#!{shutil.which('python3')}\nimport sys,time\nif '-test' in sys.argv: sys.exit(0)\ntime.sleep(60)\n")
        self.mock("curl", f'''#!{shutil.which('python3')}
import os,sys
from pathlib import Path
a=sys.argv[1:]
port=a[a.index('--proxy')+1].rsplit(':',1)[1]
active=Path(os.environ['HOME_VPN_ROOT']+'/etc/xray/configs/04_outbounds.json').read_text().strip()
health=os.environ.get('PROBE_HEALTH' if port=='10818' else 'HOME_HEALTH','up') if port=='10818' or active=='home' else os.environ.get('FALLBACK_HEALTH','up') if active=='fallback' else 'up'
if health=='down' or (health=='partial' and 'youtube' in a[-1]):
 print('000 0.000 0.000 12.000',end=''); print('curl: (28) Connection timed out',file=sys.stderr); sys.exit(28)
out=a[a.index('-o')+1]
ip='185.234.9.26' if port=='10818' or active=='home' else '203.0.113.10'
if os.environ.get('WRONG_IP')=='yes': ip='203.0.113.99'
if out!='/dev/null': Path(out).write_text('ip='+ip+'\\n')
print(('204' if 'youtube' in a[-1] else '200')+' 0.01 0.02 0.03',end='')
''')

    def mock(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def run_manager(self):
        return subprocess.run([str(self.root / "sbin/home-vpn-auto"), "run"], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def log(self, *args):
        return subprocess.run([str(self.root / "sbin/home-vpn-log"), *args], env=self.env,
                              capture_output=True, text=True, check=True, timeout=10)

    def archives(self):
        return sorted((self.root / "var/log/home-vpn/incidents").glob("*.log.gz"))

    def test_healthy_primary_does_not_restart(self):
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertFalse((self.state / "restarts").exists())
        self.assertEqual(self.archives(), [])

    def test_external_fallback_change_is_archived(self):
        self.active.write_text("fallback\n")
        (self.state / "mode").write_text("fallback\n")
        self.env["PROBE_HEALTH"] = "down"
        self.run_manager()
        self.active.write_text("amnezia\n")
        self.run_manager()
        self.assertIn("external_outbound_change", gzip.decompress(self.archives()[0].read_bytes()).decode())

    def test_one_failed_site_does_not_failover(self):
        self.env["HOME_HEALTH"] = "partial"
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertEqual(self.active.read_text().strip(), "home")
        self.assertFalse((self.state / "restarts").exists())

    def test_two_failed_checks_save_evidence_and_fallback(self):
        self.env.update(HOME_HEALTH="down", PROBE_HEALTH="down")
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertEqual(self.active.read_text().strip(), "home")
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertEqual(self.active.read_text().strip(), "fallback")
        self.assertEqual((self.state / "mode").read_text().strip(), "fallback")
        archive = self.archives()[0]
        content = gzip.decompress(archive.read_bytes()).decode()
        self.assertIn("Connection timed out", content)
        self.assertIn("historical diagnostic evidence", content)
        self.assertIn("consecutive_primary_failures", content)
        self.assertIn("switch_success", archive.with_name(archive.name.replace(".log.gz", ".result")).read_text())

    def test_recovery_requires_two_distinct_cycles_and_egress(self):
        self.active.write_text("fallback\n")
        (self.state / "mode").write_text("fallback\n")
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertEqual(self.active.read_text().strip(), "fallback")
        self.assertEqual((self.state / "recovery-successes").read_text().strip(), "1")
        self.run_manager()  # A repeated invocation in the same minute cannot count twice.
        self.assertEqual(self.active.read_text().strip(), "fallback")
        (self.state / "last-recovery").write_text(str(int(time.time()) - 60))
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertEqual(self.active.read_text().strip(), "home")
        self.assertEqual((self.state / "mode").read_text().strip(), "home")
        self.assertIn("private_recovered", gzip.decompress(self.archives()[0].read_bytes()).decode())

    def test_wrong_egress_never_recovers(self):
        self.active.write_text("fallback\n")
        (self.state / "mode").write_text("fallback\n")
        self.env["WRONG_IP"] = "yes"
        self.run_manager()
        self.assertEqual(self.active.read_text().strip(), "fallback")
        self.assertEqual((self.state / "recovery-successes").read_text().strip(), "0")

    def test_dead_primary_and_blanc_continue_to_pool_recovery(self):
        self.env.update(HOME_HEALTH="down", FALLBACK_HEALTH="down", PROBE_HEALTH="down")
        self.run_manager()
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertEqual(self.active.read_text().strip(), "amnezia")
        self.assertTrue((self.state / "pool-recovery").exists())
        self.assertEqual((self.state / "mode").read_text().strip(), "fallback")

    def test_failed_post_switch_rolls_back_and_preserves_logs(self):
        self.active.write_text("fallback\n")
        (self.state / "mode").write_text("fallback\n")
        (self.state / "last-recovery").write_text(str(int(time.time()) - 60))
        (self.state / "recovery-successes").write_text("1\n")
        self.env["HOME_HEALTH"] = "down"
        self.run_manager()
        self.assertEqual(self.active.read_text().strip(), "fallback")
        self.assertEqual((self.state / "mode").read_text().strip(), "fallback")
        self.assertEqual(len(self.archives()), 2)
        all_logs = "\n".join(gzip.decompress(p.read_bytes()).decode() for p in self.archives())
        self.assertIn("post-switch-home", all_logs)
        self.assertIn("Connection timed out", all_logs)

    def test_rotation_limits_and_live_log_caps(self):
        ring = self.root / "var/log/home-vpn/rolling"
        ring.mkdir(parents=True)
        minute = int(time.time()) // 60
        (ring / f"{minute - 16}.health").write_text("old")
        (ring / f"{minute - 1}.health").write_text("recent")
        (self.root / "var/log/xray/error.log").write_bytes(b"x" * 600000)
        (self.root / "var/log/xray/access.log").write_bytes(b"y" * 300000)
        self.log("sample")
        self.assertFalse((ring / f"{minute - 16}.health").exists())
        self.assertTrue((ring / f"{minute - 1}.health").exists())
        self.assertLessEqual((self.root / "var/log/xray/error.log").stat().st_size, 262144)
        self.assertLessEqual((self.root / "var/log/xray/access.log").stat().st_size, 131072)
        for i in range(10): self.log("incident", f"retention-test-{i}")
        self.assertLessEqual(len(self.archives()), 8)
        # Verify the byte limit separately with incompressible fake archives.
        for i in range(8):
            (self.root / f"var/log/home-vpn/incidents/9999999{i}.log.gz").write_bytes(b"z" * 1500000)
        self.log("sample")
        self.assertLessEqual(sum(p.stat().st_size for p in self.archives()), 8388608)


if __name__ == "__main__":
    unittest.main()
