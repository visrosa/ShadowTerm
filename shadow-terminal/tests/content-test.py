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
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


content = module('content-service')
definitions = module('completion-definitions')
details = module('context-details')


class ContentTests(unittest.TestCase):
    def test_directory_details_and_read_only_ranking(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "parent ' 日本語"
            root.mkdir()
            child = root / "child\n$variable; '"
            child.mkdir()
            frequent = Path(directory) / "frequent"
            frequent.mkdir()
            scratch = Path(directory) / 'scratch'
            scratch.mkdir()
            database = Path(directory) / 'zoxide'
            database.mkdir()
            (database / 'db.zo').write_bytes(b'fixture database')
            calls = []
            def ranked(argv, cwd, extra_env):
                calls.append((argv, cwd, extra_env))
                self.assertEqual((Path(extra_env['_ZO_DATA_DIR']) / 'db.zo').read_bytes(), b'fixture database')
                (Path(extra_env['_ZO_DATA_DIR']) / 'db.zo').write_bytes(b'query rewrote snapshot')
                return str(frequent) + "\n" + str(root) + "\n"
            with mock.patch.object(details.shutil, 'which', return_value='/fixture/zoxide'), mock.patch.dict(os.environ, {'_ZO_DATA_DIR': str(database)}):
                result = details.directory_details(str(root), ranked, scratch)
            paths = [row['path'] for row in result['entries']]
            self.assertIn(str(child), paths)
            self.assertIn(str(root.parent), paths)
            self.assertIn(str(frequent), paths)
            self.assertEqual(calls, [(['zoxide', 'query', '--list'], str(root), {'_ZO_DATA_DIR': str(scratch)})])
            self.assertEqual((database / 'db.zo').read_bytes(), b'fixture database')
            with mock.patch.object(details.shutil, 'which', return_value=None):
                self.assertIn('unavailable', details.directory_details(str(root), ranked, scratch)['notice'])
            for index in range(540):
                (root / str(index)).touch()
            with mock.patch.object(details.shutil, 'which', return_value=None):
                result = details.directory_details(str(root), ranked, scratch)
            self.assertTrue(result['truncated'])
            self.assertLessEqual(len(result['entries']), 38)

    def test_real_zoxide_snapshot_preserves_original(self):
        if not details.shutil.which('zoxide'):
            self.skipTest('zoxide is optional')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'visited'
            target.mkdir()
            database = root / 'database'
            scratch = root / 'scratch'
            scratch.mkdir()
            env = os.environ | {'_ZO_DATA_DIR': str(database)}
            subprocess.run(['zoxide', 'add', '--', str(target)], env=env, check=True)
            original = (database / 'db.zo').read_bytes()
            with mock.patch.dict(os.environ, {'_ZO_DATA_DIR': str(database)}):
                result = details.directory_details(str(target), content.run, scratch)
            self.assertEqual((database / 'db.zo').read_bytes(), original)
            self.assertTrue((scratch / 'db.zo').is_file())
            self.assertIn('Ranked by zoxide', result['notice'])

    def test_git_context_rename_worktree_and_repository_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo ' 日本語"
            root.mkdir()
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)
            git('init', '-q', '--initial-branch=main')
            original = 'old\nname.txt'
            (root / original).write_text('fixture')
            git('add', '--', original)
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
            git('mv', '--', original, 'new\nname.txt')
            (root / 'untracked').write_text('fixture')
            git('branch', 'feature/日本語')
            with mock.patch.dict(os.environ, {'GIT_DIR': '/missing/wrong-repository'}):
                result = details.git_details(str(root), content.run)
            self.assertEqual(result['root'], str(root))
            self.assertEqual(result['total'], 2)
            self.assertTrue(any('old\\nname.txt' in row and 'new\\nname.txt' in row for row in result['files']))
            self.assertIn('feature/日本語', [row['name'] for row in result['branches']])
            linked = Path(directory) / 'linked'
            git('worktree', 'add', '-qb', 'linked', str(linked))
            result = details.git_details(str(linked), content.run)
            self.assertEqual(result['root'], str(linked))
            self.assertTrue(any(row['name'] == 'linked' and row['current'] for row in result['branches']))
            self.assertEqual(result['files'], [])
            git('worktree', 'remove', '--force', str(linked))

    def test_binary_provider_framing_and_bounds(self):
        self.assertEqual(content.run([sys.executable, '-c', 'import sys; sys.stdout.buffer.write(bytes([97,0,98]))'], binary=True), b'a\0b')
        with self.assertRaises(ValueError):
            content.run([sys.executable, '-c', 'print("x"*50000)'], binary=True)

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
