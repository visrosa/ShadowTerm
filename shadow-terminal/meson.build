project('shadow-term', 'vala', 'c', version: '0.0.1')

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
executable('shadow-term', 'src/options.vala', 'src/application.vala', 'src/placement.c',
           editor, dependencies: deps, vala_args: ['--pkg=posix'],
           c_args: cflags, include_directories: include_directories('src'), install: false)
options_test = executable('options-test', 'src/options.vala', 'tests/options-test.vala',
                          dependencies: dependency('json-glib-1.0'))
test('options', options_test)
