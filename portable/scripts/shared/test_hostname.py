"""Tests for hostname inference from SYSTEM_DOMAIN. Run: python3 -m unittest test_hostname"""

import unittest

from base_config import Config, infer_hostname


class InferHostnameTest(unittest.TestCase):
    def test_domain_only_uses_current_short_name(self):
        c = infer_hostname(Config.from_env({"SYSTEM_DOMAIN": "nodes.ishiori.net"}), "hv1002")
        self.assertEqual((c.hostname, c.fqdn), ("hv1002", "hv1002.nodes.ishiori.net"))

    def test_current_fqdn_is_cut_to_short_name_and_lowercased(self):
        c = infer_hostname(Config.from_env({"SYSTEM_DOMAIN": "nodes.ishiori.net"}), "HV1002.example.lan")
        self.assertEqual((c.hostname, c.fqdn), ("hv1002", "hv1002.nodes.ishiori.net"))

    def test_explicit_hostname_is_left_alone(self):
        c = Config.from_env({"SYSTEM_HOSTNAME": "web1", "SYSTEM_DOMAIN": "nodes.ishiori.net"})
        self.assertIs(infer_hostname(c, "hv1002"), c)

    def test_no_domain_is_left_alone(self):
        c = Config.from_env({})
        self.assertIs(infer_hostname(c, "hv1002"), c)

    def test_explicit_fqdn_is_left_alone(self):
        c = Config.from_env({"SYSTEM_DOMAIN": "nodes.ishiori.net", "SYSTEM_FQDN": "web1.example.org"})
        self.assertIs(infer_hostname(c, "hv1002"), c)

    def test_generic_or_unusable_names_are_refused(self):
        c = Config.from_env({"SYSTEM_DOMAIN": "nodes.ishiori.net"})
        for current in ("localhost", "localhost.localdomain", "(none)", "", "bad_name", "-leading"):
            with self.subTest(current=current):
                with self.assertRaises(ValueError):
                    infer_hostname(c, current)

    def test_error_class_is_configurable(self):
        class Boom(RuntimeError):
            pass
        c = Config.from_env({"SYSTEM_DOMAIN": "nodes.ishiori.net"})
        with self.assertRaises(Boom):
            infer_hostname(c, "localhost", Boom)


if __name__ == "__main__":
    unittest.main()
