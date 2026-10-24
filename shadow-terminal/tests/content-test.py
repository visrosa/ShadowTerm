#!/usr/bin/env python3
"""Headless contracts for lookup, bounded content, native rules and fish export."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


content = module('content-service')
definitions = module('completion-definitions')


class ContentTests(unittest.TestCase):
    def test_caret_scope(self):
        source = 'echo (task list)'
        for cursor in range(6, 15):
            self.assertEqual(content.lookup(source, cursor)['command'], 'task')
        self.assertEqual(content.lookup(source, 2)['command'], 'echo')
        self.assertEqual(content.lookup(source, 16)['command'], 'echo')
        self.assertEqual(content.lookup('echo (task (git log))', 16)['command'], 'git')
        self.assertEqual(content.lookup('echo (task li', 12)['command'], 'task')
        for source in ["echo '(task list)'", r'echo \(task\)', 'echo "literal (task)"']:
            self.assertEqual(content.lookup(source, 9)['command'], 'echo')
        self.assertEqual(content.lookup('echo "$(task list)"', 12)['command'], 'task')
        self.assertEqual(content.lookup('echo ok | task list', 17)['command'], 'task')
        self.assertEqual(content.lookup('echo # (fake)\n task list', 22)['command'], 'task')
        self.assertEqual(content.lookup('task list', 4, 'git')['query'], 'git')
        self.assertEqual(content.lookup('task list', 4, '--help')['query'], 'task')

    def test_previews(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'text').write_text('日本語\n' + 'x' * 60000)
            result = content.preview('text', directory)
            self.assertTrue(result.startswith('日本語'))
            self.assertIn('truncated', result)
            (root / 'binary').write_bytes(b'a\0b')
            self.assertIn('Binary', content.preview('binary', directory))
            os.mkfifo(root / 'fifo')
            self.assertIn('special', content.preview('fifo', directory))
            self.assertIn('text', content.preview('.', directory))

    def test_sources_and_literal_query(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'sources.json'
            config.write_text(json.dumps({'sources': [{'name': 'Fixture', 'argv': [sys.executable, '-c', 'import sys; print(sys.argv[1])', '{query}']}]}))
            query = '$(touch SHOULD-NOT-EXIST); 日本語'
            result = content.respond({'kind': 'document', 'context': {'query': query, 'selection': query}, 'config': str(config), 'index': 0, 'cwd': directory})
            self.assertEqual(result.strip(), query)
            self.assertFalse((Path(directory) / 'SHOULD-NOT-EXIST').exists())
            self.assertEqual(content.sources(str(config))[0]['name'], 'Fixture')
            with self.assertRaises(TimeoutError):
                content.run([sys.executable, '-c', 'import time; time.sleep(5)'])

    def test_fish_export(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'fixture.json'
            schema = {'version': 1, 'command': 'vcomfixture', 'rules': [
                {'long': 'color', 'description': 'Color option', 'requires_argument': True, 'files': 'disable',
                 'values': [{'value': '日本語', 'description': 'Unicode choice'}, {'value': "a'b", 'description': 'Quoted choice'}]},
                {'long': 'detail', 'when_subcommand': 'list', 'description': 'Only for list'},
                {'long': 'dynamic', 'requires_argument': True, 'files': 'disable',
                 'dynamic': [sys.executable, '-c', "print('dynamic-value\\tDynamic description')"]}]}
            config.write_text(json.dumps(schema))
            generated = definitions.export(config)
            self.assertEqual(generated, definitions.export(config))
            fish = root / 'fixture.fish'
            fish.write_text(generated)
            env = os.environ | {f'XDG_{name}_HOME': str(root / name.lower()) for name in ['CONFIG', 'DATA', 'CACHE', 'STATE']} | {'fish_history': 'vcom_definition_fixture'}
            for key, value in env.items():
                if key.startswith('XDG_') and key.endswith('_HOME'):
                    Path(value).mkdir(exist_ok=True)
            command = 'set fish_complete_path; source $argv[1]; complete -C $argv[2]'
            def candidates(source):
                return subprocess.check_output(['fish', '--no-config', '-c', command, str(fish), source], env=env, text=True)
            self.assertIn('--color\tColor option', candidates('vcomfixture --col'))
            self.assertIn('日本語\tUnicode choice', candidates('vcomfixture --color '))
            self.assertIn("a'b", candidates('vcomfixture --color '))
            self.assertNotIn('--detail', candidates('vcomfixture --det'))
            # Fish's autoload helpers are necessary for structured conditions;
            # source the upstream helper explicitly in this no-config fixture.
            with fish.open('a') as out:
                out.write('\nsource /usr/share/fish/functions/__fish_seen_subcommand_from.fish\n')
            self.assertIn('--detail', candidates('vcomfixture list --det'))
            self.assertIn('dynamic-value\tDynamic description', candidates('vcomfixture --dynamic '))
            context = {'words': ['vcomfixture', '--color'], 'command': 'vcomfixture', 'prefix': '', 'cwd': directory}
            native = definitions.complete(context, directory)
            self.assertTrue(native['complete'])
            self.assertIn('日本語', [v['value'] for v in native['items']])
            schema['rules'][0]['unsupported'] = True
            config.write_text(json.dumps(schema))
            with self.assertRaises(ValueError):
                definitions.export(config)


if __name__ == '__main__':
    unittest.main()
