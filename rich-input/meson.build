project('vibrant-rich-input', 'vala', 'c', version: '0.1.0')

deps = [dependency('gtk4', version: '>=4.12'), dependency('granite-7'),
        dependency('vte-2.91-gtk4'), dependency('json-glib-1.0')]
executable('vibrant-rich-input', 'src/editor.vala', 'src/application.vala',
           dependencies: deps, c_args: ['-DGETTEXT_PACKAGE="vibrant-rich-input"'], install: false)
editor_test = executable('editor-test', 'src/editor.vala', 'tests/editor-test.vala',
                         dependencies: dependency('gtk4'))
test('editor', editor_test)
