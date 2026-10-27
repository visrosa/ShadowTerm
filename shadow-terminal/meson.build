project('shadow-term', 'vala', 'c', version: '0.0.9')

private_vte = get_option('vte-library-dir')
if private_vte != '' and not import('fs').is_file(private_vte / 'libvte-2.91-gtk4.so')
  error('Prepare the private VTE library before setting vte-library-dir')
endif

deps = [dependency('gtk4', version: '>=4.12'), dependency('granite-7', version: '>=7.7'),
        dependency('vte-2.91-gtk4', version: '>=0.78'), dependency('json-glib-1.0')]
pcre2 = dependency('libpcre2-8')
# Only the C hit-testing helper uses PCRE2's compile-flag constants.
app_includes = [include_directories('src'), include_directories(pcre2.get_variable(pkgconfig: 'includedir'))]
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
config.set_quoted('CONTENT_SERVICE_PATH', meson.current_source_dir() / 'content-service.py')
config.set_quoted('SHELL_HELPER_PATH', meson.current_build_dir() / 'vcom-shell')
config.set_quoted('FISH_INTEGRATION_PATH', meson.current_source_dir() / 'integration/fish.fish')
config.set('PRIVATE_VTE', private_vte != '' ? 'true' : 'false')
paths = configure_file(input: 'src/config.vala.in', output: 'config.vala', configuration: config)
gnome = import('gnome')
resources = gnome.compile_resources('shadow-resources', 'data/resources.xml', source_dir: 'data', c_name: 'shadow')
executable('vcom-shell', 'src/shell-helper.c', dependencies: dependency('gio-2.0'), install: false)
app_sources = files('src/options.vala', 'src/application.vala', 'src/workspace.vala', 'src/palette.vala',
                    'src/terminal-context.vala', 'src/word-selection.vapi', 'src/word-selection.c', 'src/placement.c',
                    'src/input-session.vala', 'src/shell-bridge.vala', 'src/preferences.vala', 'src/context.vala',
                    'src/content-client.vala', 'src/content-service.vala', 'src/prompt-context.vala', 'src/context-bar.vala', 'src/fish-services.vala', 'src/fish-analysis.vala')
app_sources += [paths, editor, completion, assistance, resources]
executable('shadow-term', app_sources, dependencies: deps, vala_args: ['--pkg=posix'],
           c_args: cflags, include_directories: app_includes, build_rpath: private_vte, install: false)
executable('presentation-test', app_sources, 'tests/presentation-test.vala', dependencies: deps,
           vala_args: ['--pkg=posix', '--define=PRESENTATION_TEST'], c_args: cflags,
           include_directories: app_includes, build_rpath: private_vte, install: false)
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
context_test = executable('context-test', 'src/context.vala', 'src/prompt-context.vala', 'tests/context-test.vala', dependencies: dependency('gio-2.0'))
test('repository-context', context_test)
fish_services_test = executable('fish-services-test', 'src/fish-services.vala', 'src/content-client.vala', paths, completion, 'tests/fish-services-test.vala',
                               dependencies: [dependency('gio-2.0'), dependency('json-glib-1.0')], vala_args: ['--pkg=posix'])
test('fish-services', fish_services_test)
editor_checks = configure_file(input: '../rich-input/tests/editor-test.vala',
                               output: 'editor-test.vala', copy: true)
executable('editor-test', editor, completion, assistance, editor_checks, dependencies: dependency('gtk4'), install: false)
executable('appearance-test', 'src/preferences.vala', 'tests/appearance-test.vala', dependencies: dependency('gtk4'), install: false)

python = find_program('python3')
test('content-services', python, args: [meson.current_source_dir() / 'tests/content-test.py'], timeout: 15)
