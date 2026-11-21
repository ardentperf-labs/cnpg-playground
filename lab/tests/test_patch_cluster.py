import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('patch_cluster', Path(__file__).parents[1] / 'patch-cluster.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class OverlayTests(unittest.TestCase):
    def test_preserves_existing_parameters_and_named_extensions(self):
        base = {'spec': {'postgresql': {'parameters': {'max_connections': '100'},
            'extensions': [{'name': 'pgsentinel', 'image': {'reference': 'old'}}]}}}
        patch = {'spec': {'postgresql': {'parameters': {'oauth_validator_libraries': 'entra_validator'},
            'extensions': [{'name': 'postgis', 'image': {'reference': 'new'}}]}}}
        result = module.merge(base, patch)
        pg = result['spec']['postgresql']
        self.assertEqual(pg['parameters']['max_connections'], '100')
        self.assertEqual([x['name'] for x in pg['extensions']], ['pgsentinel', 'postgis'])
        import copy
        once = copy.deepcopy(result)
        self.assertEqual(module.merge(result, patch), once)

    def test_authentication_rules_replace_in_order(self):
        result = module.merge({'pg_hba': ['old rule']}, {'pg_hba': ['cert rule', 'oauth rule']})
        self.assertEqual(result['pg_hba'], ['cert rule', 'oauth rule'])


if __name__ == '__main__':
    unittest.main()
