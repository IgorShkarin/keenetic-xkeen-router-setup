#!/usr/bin/env python3
"""Safety gates for an autonomous production-service recovery."""
import copy
import unittest
from netcup_vpn_guard import decision


class RecoverySafetyTests(unittest.TestCase):
    def setUp(self):
        self.observation = {'probe_ready': True, 'proxy': {'google': False, 'cloudflare': False},
                            'direct': {'google': True, 'cloudflare': True},
                            'services': {'nginx': True, 'xray': True},
                            'listeners': {'nginx': True, 'xray': True}}

    def cycles(self, observation=None, times=(10000, 10061, 10122), previous=None):
        state = previous or {}
        for now in times:
            state = decision(state, observation or self.observation, now)
        return state

    def test_healthy_path_never_restarts(self):
        self.observation['proxy'] = {'google': True, 'cloudflare': True}
        self.assertEqual(self.cycles()['action'], 'none')

    def test_single_site_failure_is_visible_without_restart(self):
        self.observation['proxy']['google'] = True
        state = self.cycles()
        self.assertEqual((state['health'], state['action']), ('degraded', 'none'))

    def test_upstream_outage_never_restarts_local_services(self):
        self.observation['direct'] = {'google': False, 'cloudflare': False}
        self.assertEqual(self.cycles()['action'], 'none')

    def test_broken_probe_never_restarts_production(self):
        self.observation['probe_ready'] = False
        self.assertEqual(self.cycles()['health'], 'monitor_error')
        self.assertEqual(self.cycles()['action'], 'none')

    def test_fewer_than_three_failures_are_insufficient(self):
        self.assertEqual(self.cycles(times=(10000, 10122))['action'], 'none')

    def test_three_rapid_checks_are_insufficient(self):
        self.assertEqual(self.cycles(times=(10000, 10001, 10002))['action'], 'none')

    def test_repeated_local_failure_allows_one_xray_recovery(self):
        self.assertEqual(self.cycles()['action'], 'xray')

    def test_missing_frontend_targets_nginx(self):
        self.observation['listeners']['nginx'] = False
        self.assertEqual(self.cycles()['action'], 'nginx')

    def test_recent_recovery_blocks_another_restart(self):
        state = self.cycles(previous={'last_recovery': 9900})
        self.assertEqual(state['action'], 'cooldown')

    def test_long_gap_requires_new_failure_sequence(self):
        self.assertEqual(self.cycles(times=(10000, 10061, 10400))['failures'], 1)

    def test_stopped_service_is_left_to_operator_or_native_restart(self):
        self.observation['services']['xray'] = False
        self.assertEqual(self.cycles()['action'], 'none')

    def test_success_breaks_failure_sequence(self):
        state = self.cycles(times=(10000, 10061))
        good = copy.deepcopy(self.observation)
        good['proxy']['google'] = True
        state = decision(state, good, 10122)
        state = decision(state, self.observation, 10183)
        self.assertEqual((state['failures'], state['action']), (1, 'none'))

    def test_maintenance_never_restarts(self):
        self.assertEqual(self.cycles({'maintenance': True})['action'], 'none')


if __name__ == '__main__':
    unittest.main()
