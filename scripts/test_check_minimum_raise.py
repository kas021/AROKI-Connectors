import hashlib
import json
import unittest

from check_minimum_raise import (
    COMPATIBILITY_FLOOR,
    PINNED_PUBLISHER_SHA256,
    GateError,
    authorize_raise,
)


COMMIT = "2" * 40
BASE_COMMIT = "3" * 40
LEGACY_COMMIT = "4" * 40
LEGACY_INDEX_SHA = "5" * 64


class MinimumRaiseGateTests(unittest.TestCase):
    def setUp(self):
        self.old_entry = {
            "id": "anikage",
            "familyID": "anikage",
            "version": "0.3.5",
            "minimumAppVersion": "0.1.0",
        }
        self.index_bytes = json.dumps(
            {"schemaVersion": 1, "repositoryID": "fixture", "connectors": [self.old_entry]},
            sort_keys=True,
        ).encode()
        self.manifest = {
            "id": "anikage",
            "familyID": "anikage",
            "version": "0.3.6",
            "minimumAppVersion": COMPATIBILITY_FLOOR,
        }
        self.manifest_bytes = json.dumps(self.manifest, sort_keys=True).encode()
        self.expected_sha = hashlib.sha256(self.manifest_bytes).hexdigest()

    def authorize(self, **overrides):
        args = {
            "connector_id": "anikage",
            "manifest_bytes": self.manifest_bytes,
            "index_bytes": self.index_bytes,
            "registry": {"schemaVersion": 1, "approvedRaises": []},
            "compatibility_floor": COMPATIBILITY_FLOOR,
            "expected_candidate_commit": COMMIT,
            "observed_candidate_commit": COMMIT,
            "expected_manifest_sha256": self.expected_sha,
            "base_main_commit": BASE_COMMIT,
            "legacy_branch_commit": LEGACY_COMMIT,
            "legacy_index_sha256": LEGACY_INDEX_SHA,
            "publisher_script_sha256": PINNED_PUBLISHER_SHA256,
        }
        args.update(overrides)
        return authorize_raise(**args)

    def approval_registry(self):
        return {
            "schemaVersion": 1,
            "approvedRaises": [
                {
                    "connectorID": "anikage",
                    "familyID": "anikage",
                    "candidateCommit": COMMIT,
                    "candidateSHA256": self.expected_sha,
                    "baselineVersion": "0.3.5",
                    "baselineMinimumAppVersion": "0.1.0",
                    "baselineIndexSHA256": hashlib.sha256(self.index_bytes).hexdigest(),
                    "baseMainCommit": BASE_COMMIT,
                    "legacyBranchCommit": LEGACY_COMMIT,
                    "legacyIndexSHA256": LEGACY_INDEX_SHA,
                    "minimumAppVersion": COMPATIBILITY_FLOOR,
                    "publisherScriptSHA256": PINNED_PUBLISHER_SHA256,
                }
            ],
        }

    def assert_blocked(self, message, **overrides):
        with self.assertRaisesRegex(GateError, message):
            self.authorize(**overrides)

    def test_existing_minimum_behavior_needs_no_override(self):
        manifest = dict(self.manifest, minimumAppVersion="0.1.0")
        payload = json.dumps(manifest, sort_keys=True).encode()
        result = self.authorize(
            manifest_bytes=payload,
            expected_manifest_sha256=hashlib.sha256(payload).hexdigest(),
            compatibility_floor="",
        )
        self.assertEqual(result["decision"], "no-minimum-raise")

    def test_wrong_floor_is_rejected(self):
        self.assert_blocked("exact compatibility floor", compatibility_floor="2.1.37")

    def test_raise_fails_closed_with_empty_approval_registry(self):
        self.assert_blocked("no owner-reviewed candidate approval")

    def test_approved_exact_candidate_can_pass_policy_gate(self):
        result = self.authorize(registry=self.approval_registry())
        self.assertEqual(result["decision"], "approved-exact-floor-raise")

    def test_wrong_expected_manifest_hash_is_rejected(self):
        self.assert_blocked("do not match expected SHA-256", expected_manifest_sha256="6" * 64)

    def test_wrong_candidate_id_is_rejected(self):
        manifest = dict(self.manifest, id="anipm")
        payload = json.dumps(manifest, sort_keys=True).encode()
        self.assert_blocked(
            "candidate ID",
            manifest_bytes=payload,
            expected_manifest_sha256=hashlib.sha256(payload).hexdigest(),
        )

    def test_family_id_mismatch_is_rejected(self):
        manifest = dict(self.manifest, familyID="other-family")
        payload = json.dumps(manifest, sort_keys=True).encode()
        self.assert_blocked(
            "familyID",
            manifest_bytes=payload,
            expected_manifest_sha256=hashlib.sha256(payload).hexdigest(),
        )

    def test_equal_or_lower_connector_version_is_rejected(self):
        manifest = dict(self.manifest, version="0.3.5")
        payload = json.dumps(manifest, sort_keys=True).encode()
        self.assert_blocked(
            "strict upgrade",
            manifest_bytes=payload,
            expected_manifest_sha256=hashlib.sha256(payload).hexdigest(),
        )

    def test_script_drift_is_rejected_even_with_registry_entry(self):
        self.assert_blocked(
            "publisher script has drifted",
            registry=self.approval_registry(),
            publisher_script_sha256="0" * 64,
        )

    def test_candidate_commit_must_be_immutable_and_match_observed(self):
        self.assert_blocked("full 40-character", expected_candidate_commit="branch-name")
        self.assert_blocked("does not match approved commit", observed_candidate_commit="7" * 40)

    def test_registry_must_bind_the_exact_signed_index_and_legacy_branch(self):
        registry = self.approval_registry()
        registry["approvedRaises"][0]["baselineIndexSHA256"] = "8" * 64
        self.assert_blocked("baselineIndexSHA256", registry=registry)
        registry = self.approval_registry()
        registry["approvedRaises"][0]["legacyBranchCommit"] = "9" * 40
        self.assert_blocked("legacyBranchCommit", registry=registry)

    def test_raised_minimum_must_equal_floor(self):
        manifest = dict(self.manifest, minimumAppVersion="2.1.37")
        payload = json.dumps(manifest, sort_keys=True).encode()
        self.assert_blocked(
            "must equal compatibility floor",
            manifest_bytes=payload,
            expected_manifest_sha256=hashlib.sha256(payload).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
