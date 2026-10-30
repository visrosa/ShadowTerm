project('vibrant-rich-input', 'vala', 'c', version: '0.1.0')

add_project_arguments('--target-glib=2.76', language: 'vala')

deps = [dependency('gtk4', version: '>=4.12'), dependency('granite-7', version: '>=7.7'),
        dependency('vte-2.91-gtk4'), dependency('json-glib-1.0')]
executable('vibrant-rich-input', 'src/editor.vala', 'src/completion.vala', 'src/assistance.vala', 'src/application.vala', 'src/terminal-bytes.vapi', 'src/byte-buffer.vapi',
           dependencies: deps, include_directories: include_directories('src'), c_args: ['-DGETTEXT_PACKAGE="vibrant-rich-input"'], install: false)
editor_test = executable('editor-test', 'src/editor.vala', 'src/completion.vala', 'src/assistance.vala', 'tests/editor-test.vala',
                         dependencies: dependency('gtk4'))
test('editor', editor_test)
completion_test = executable('completion-test', 'src/completion.vala', 'tests/completion-test.vala', dependencies: dependency('gio-2.0'))
test('completion', completion_test)

consumer_test = executable('consumer-test', 'src/source-session.vala', 'tests/consumer-test.vala', dependencies: dependency('gio-2.0'))
test('consumer-contract', consumer_test)
