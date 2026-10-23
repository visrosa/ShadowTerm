project('shadow-term', 'vala', 'c', version: '0.0.4')

deps = [dependency('gtk4', version: '>=4.12'), dependency('granite-7', version: '>=7.7'),
        dependency('vte-2.91-gtk4', version: '>=0.78'), dependency('json-glib-1.0')]
x11 = dependency('gtk4-x11', required: false)
xlib = dependency('x11', required: false)
cflags = ['-DGETTEXT_PACKAGE="shadow-term"']
if x11.found() and xlib.found()
  deps += [x11, xlib]
  cflags += ['-DHAVE_X11']
endif
editor = configure_file(input: '../rich-input/src/editor.vala', output: 'editor.vala', copy: true)
completion = configure_file(input: '../rich-input/src/completion.vala', output: 'completion.vala', copy: true)
assistance = configure_file(input: '../rich-input/src/assistance.vala', output: 'assistance.vala', copy: true)
config = configuration_data()
config.set_quoted('SHELL_HELPER_PATH', meson.current_build_dir() / 'vcom-shell')
config.set_quoted('FISH_INTEGRATION_PATH', meson.current_source_dir() / 'integration/fish.fish')
paths = configure_file(input: 'src/config.vala.in', output: 'config.vala', configuration: config)
executable('vcom-shell', 'src/shell-helper.c', dependencies: dependency('gio-2.0'), install: false)
app_sources = files('src/options.vala', 'src/application.vala', 'src/placement.c',
                    'src/input-session.vala', 'src/shell-bridge.vala', 'src/preferences.vala', 'src/context.vala')
app_sources += [paths, editor, completion, assistance]
executable('shadow-term', app_sources, dependencies: deps, vala_args: ['--pkg=posix'],
           c_args: cflags, include_directories: include_directories('src'), install: false)
executable('presentation-test', app_sources, 'tests/presentation-test.vala', dependencies: deps,
           vala_args: ['--pkg=posix', '--define=PRESENTATION_TEST'], c_args: cflags,
           include_directories: include_directories('src'), install: false)
options_test = executable('options-test', 'src/options.vala', 'tests/options-test.vala',
                          dependencies: dependency('json-glib-1.0'))
test('options', options_test)
input_test = executable('input-test', 'src/input-session.vala', 'tests/input-test.vala',
                        dependencies: dependency('gio-2.0'))
test('input-session', input_test)
completion_checks = configure_file(input: '../rich-input/tests/completion-test.vala',
                                   output: 'completion-test.vala', copy: true)
completion_test = executable('completion-test', completion, completion_checks, dependencies: dependency('gio-2.0'))
test('completion', completion_test)
preferences_test = executable('preferences-test', 'src/preferences.vala', 'tests/preferences-test.vala', dependencies: dependency('gtk4'))
test('preferences', preferences_test)
context_test = executable('context-test', 'src/context.vala', 'tests/context-test.vala', dependencies: dependency('gio-2.0'))
test('repository-context', context_test)
editor_checks = configure_file(input: '../rich-input/tests/editor-test.vala',
                               output: 'editor-test.vala', copy: true)
executable('editor-test', editor, completion, assistance, editor_checks, dependencies: dependency('gtk4'), install: false)
executable('appearance-test', 'src/preferences.vala', 'tests/appearance-test.vala', dependencies: dependency('gtk4'), install: false)
