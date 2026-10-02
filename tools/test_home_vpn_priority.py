"""Regression checks for connection-preserving explicit VPN priority."""
import os
import shutil
import time
import unittest
from test_home_vpn_auto import RouterFixture, TOOLS
from home_vpn_priority import build


class PriorityFixture(RouterFixture):
    def setUp(self):
        super().setUp()
        shutil.copyfile(TOOLS / 'home-vpn-priority.sh', self.root / 'sbin/home-vpn-priority')
        (self.root / 'sbin/home-vpn-priority').chmod(0o755)
        (self.state / 'api-enabled').touch()
        self.env.update(PRIMARY_HEALTH='up', H1_HEALTH='down', BLANC_HEALTH='up', AMNEZIA_HEALTH='down')
        python = shutil.which('python3')
        self.mock('xray', f'''#!{python}
import os,sys
from pathlib import Path
s=Path(os.environ['HOME_VPN_ROOT'])/'var/lib/home-vpn-auto'
if os.environ.get('API_FAIL')=='yes':sys.exit(1)
(s/'api-target').write_text(sys.argv[-1])
''')
        self.mock('curl', f'''#!{python}
import os,sys
from pathlib import Path
a=sys.argv[1:];s=Path(os.environ['HOME_VPN_ROOT'])/'var/lib/home-vpn-auto'
port=a[a.index('--proxy')+1].rsplit(':',1)[1]
tag={{'10821':'vless-reality','10824':'home-h1-reserve','10822':'reserve-blanc','10823':'reserve-amnezia'}}.get(port)
if port=='10809':tag=(s/'api-target').read_text()
key={{'vless-reality':'PRIMARY_HEALTH','home-h1-reserve':'H1_HEALTH','reserve-blanc':'BLANC_HEALTH','reserve-amnezia':'AMNEZIA_HEALTH'}}[tag]
if os.environ[key]=='down' or (port=='10809' and tag=='reserve-blanc' and os.environ.get('POST_FAIL')=='yes'):
 print('000',end='');sys.exit(28)
out=a[a.index('-o')+1];ip='185.234.9.26' if tag in ['vless-reality','home-h1-reserve'] else '203.0.113.10'
if out!='/dev/null':Path(out).write_text('ip='+ip+'\\n')
print('204' if 'youtube' in a[-1] else '200',end='')
''')

    # Inherited tests exercise the legacy file-swapping manager, not this mode.
    def test_primary_keeps_process(self):
        self.assertEqual(self.run_manager().returncode, 0)
        self.assertEqual((self.state / 'api-target').read_text(), 'vless-reality')
        self.assertFalse((self.state / 'restarts').exists())
        self.assertFalse((self.state / 'pool-recovery').exists())

    def test_primary_failure_selects_blanc_without_restart(self):
        self.env['PRIMARY_HEALTH'] = 'down'
        self.run_manager(); self.run_manager()
        self.assertEqual((self.state / 'selected').read_text().strip(), 'reserve-blanc')
        self.assertEqual((self.state / 'mode').read_text().strip(), 'fallback')
        self.assertEqual((self.state / 'health').read_text().strip(), 'healthy')
        self.assertFalse((self.state / 'restarts').exists())

    def test_dead_reserves_do_not_replace_primary(self):
        self.env.update(PRIMARY_HEALTH='down', BLANC_HEALTH='down')
        self.run_manager(); self.run_manager()
        self.assertEqual((self.state / 'api-target').read_text(), 'vless-reality')
        self.assertEqual((self.state / 'health').read_text().strip(), 'all-paths-down')
        self.assertFalse((self.state / 'restarts').exists())

    def test_our_h1_reserve_precedes_blanc(self):
        self.env.update(PRIMARY_HEALTH='down', H1_HEALTH='up')
        self.run_manager(); self.run_manager()
        self.assertEqual((self.state / 'selected').read_text().strip(), 'home-h1-reserve')
        self.assertEqual((self.state / 'mode').read_text().strip(), 'home')

    def test_recovery_needs_three_separate_cycles(self):
        (self.state / 'selected').write_text('reserve-blanc')
        (self.state / 'mode').write_text('fallback')
        (self.state / 'last-fallback').write_text(str(int(time.time()) - 240))
        for cycle in range(3):
            (self.state / 'last-recovery').write_text(str(int(time.time()) - 60))
            self.run_manager()
            expected = 'vless-reality' if cycle == 2 else 'reserve-blanc'
            self.assertEqual((self.state / 'api-target').read_text(), expected)
        self.assertFalse((self.state / 'restarts').exists())

    def test_failed_postcheck_rolls_back_api_selection(self):
        self.env.update(PRIMARY_HEALTH='down', POST_FAIL='yes')
        self.run_manager(); self.run_manager()
        self.assertEqual((self.state / 'api-target').read_text(), 'vless-reality')
        self.assertEqual((self.state / 'mode').read_text().strip(), 'home')
        self.assertFalse((self.state / 'restarts').exists())

    def test_api_failure_does_not_restart_or_select(self):
        self.env['API_FAIL'] = 'yes'
        self.assertEqual(self.run_manager().returncode, 1)
        self.assertFalse((self.state / 'api-target').exists())
        self.assertFalse((self.state / 'restarts').exists())


# Exclude inherited legacy scenarios from this fixture only.
for name in list(RouterFixture.__dict__):
    if name.startswith('test_'):
        setattr(PriorityFixture, name, None)


class ConfigChecks(unittest.TestCase):
    def test_relay_references_and_direct_rules_are_preserved(self):
        primary = {'outbounds': [{'tag': 'vless-reality', 'protocol': 'vless'},
                                 {'tag': 'direct', 'protocol': 'freedom'}]}
        blanc = {'outbounds': [{'tag': 'vless-reality', 'protocol': 'vless'}]}
        amnezia = {'outbounds': [
            {'tag': 'vless-reality', 'protocol': 'vless', 'streamSettings': {'sockopt': {'dialerProxy': 'proxy-relay'}}},
            {'tag': 'proxy-relay', 'protocol': 'vless'}]}
        routing = {'routing': {'rules': [{'outboundTag': 'direct', 'domain': ['example.org']},
                                        {'outboundTag': 'vless-reality', 'domain': ['youtube.com']}]}}
        result = build(primary, blanc, amnezia, routing)
        relay = result['04_outbounds.json']['outbounds'][3]['streamSettings']['sockopt']['dialerProxy']
        self.assertEqual(relay, 'reserve-amnezia-proxy-relay')
        rules = result['05_routing.json']['routing']['rules']
        self.assertEqual(rules[-2], routing['routing']['rules'][0])
        self.assertEqual(rules[-1]['balancerTag'], 'home-priority')
        self.assertTrue(all(i['listen'] == '127.0.0.1' for i in result['07_home_api.json']['inbounds']))


if __name__ == '__main__':
    # RouterFixture is imported for helpers; run only this file's new scenarios.
    suite = unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(PriorityFixture),
                               unittest.defaultTestLoader.loadTestsFromTestCase(ConfigChecks)])
    raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
