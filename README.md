Usage: mdMake [specials] ...

        specials:
                (required) TARGETS=[debug|release|optdebug] (or any comma separated combination)
                        controls which targets to build
                (optional) VERBOSE=yes
                        specifies verbose TTY output while building
                (optional) clean
                        only cleans project in current directory
                (optional) cleandeps
                        only cleans dependant projects of the project in current directory
                (optional) cleanall
                        cleans dependent projects and project in current directory
                (optional) rebuild
                        does a cleanall followed by a build
                (optional) verbose
                        prints out extra debugging TTY related to the build system

        Anything that comes after the specials is passed verbatim to the make system and is interpreted by it.
        See mdMake.common for which variable the make system uses

TODO: more
