"""Validate read-only catalog candidates; never grant comparison authority."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / 'Docs/QA/ReleasePreparation20261002'
FILE = DOC / 'development-seed-candidates-v1.json'


def validate_projection(value):
    if (value.get('project') != 'hnkplvyegonlhumlejst'
            or value.get('status') != 'BLOCKED'
            or value.get('authority_verified') is not False
            or 'cases' in value):
        raise ValueError('candidate_is_not_an_authorized_manifest')
    requested = {tuple(x) for x in value['products_requested']}
    found, keys, product_owners, variant_owners, size_owners = set(), set(), {}, {}, {}
    for row in value['candidates']:
        pair = row['source_code'], row['source_product_key']
        if pair not in requested:
            raise ValueError('unexpected_product')
        found.add(pair)
        product, variant, observation = (row[k] for k in
            ('product_id', 'variant_id', 'source_observation_id'))
        for identity in (product, variant, observation):
            uuid.UUID(identity)
        key = observation, variant
        if key in keys:
            raise ValueError('duplicate_observation_variant')
        keys.add(key)
        if product_owners.setdefault(product, pair) != pair:
            raise ValueError('product_identity_conflict')
        if variant_owners.setdefault(variant, product) != product:
            raise ValueError('variant_identity_conflict')
        sizes = row['sizes']
        if len({x['product_size_id'] for x in sizes}) < 2:
            raise ValueError('two_exact_sizes_required')
        for size in sizes:
            identity = size['product_size_id']
            uuid.UUID(identity)
            if size_owners.setdefault(identity, variant) != variant:
                raise ValueError('size_identity_conflict')
            if (not size['source_size_key']
                    or size['source_size_key'] != size['observation_size_identity']):
                raise ValueError('observation_size_identity_mismatch')
            if not isinstance(size['raw_measurements'], list):
                raise ValueError('raw_measurements_missing')
            if 'canonicalMeasurementCount' in size:
                raise ValueError('canonical_expectation_was_not_verified')
    if found != requested:
        raise ValueError('requested_product_missing')


class DevelopmentSeedCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(FILE.read_text())

    def test_frozen_development_projection_preserves_exact_identities(self):
        expected, name = (DOC / 'development-seed-candidates-v1.sha256').read_text().strip().split('  ')
        self.assertEqual(name, FILE.name)
        self.assertEqual(hashlib.sha256(FILE.read_bytes()).hexdigest(), expected)
        validate_projection(self.data)
        self.assertEqual(len(self.data['candidates']), 81)
        self.assertEqual(len(self.data['products_requested']), 6)

    def test_wrong_size_or_authority_promotion_cannot_pass(self):
        for failure in ('wrong_size', 'pretend_authorized', 'production', 'runnable_manifest'):
            with self.subTest(failure=failure):
                value = copy.deepcopy(self.data)
                if failure == 'wrong_size':
                    value['candidates'][0]['sizes'][0]['observation_size_identity'] = 'another-size'
                elif failure == 'pretend_authorized':
                    value['authority_verified'] = True
                elif failure == 'production':
                    value['project'] = 'aqhrupgjpmrtnystottx'
                else:
                    value['cases'] = []
                with self.assertRaises(ValueError):
                    validate_projection(value)


if __name__ == '__main__':
    unittest.main()
