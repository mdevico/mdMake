#!/usr/bin/env ruby

module Index
    BUILDFLAG = 0
    OUTDIR = 1
    OUTPUT = 2
    LINKDST = 3
end

if (ARGV.length == 0)
    banner = String.new

    banner =  "\n"
    banner += "Usage: mdMake [specials] ...\n"
    banner += "\n"
    banner += "\tspecials:\n"
    banner += "\t\t(required) TARGETS=[debug|release|optdebug] (or any comma separated combination)\n"
    banner += "\t\t\tcontrols which targets to build\n"
    banner += "\t\t(optional) VERBOSE=yes\n"
    banner += "\t\t\tspecifies verbose output while building\n"
    banner += "\t\t(optional) clean\n"
    banner += "\t\t\tonly cleans project in current directory\n"
    banner += "\t\t(optional) cleandeps\n"
    banner += "\t\t\tonly cleans dependant projects of the project in current directory\n"
    banner += "\t\t(optional) cleanall\n"
    banner += "\t\t\tcleans dependant projects and project in current directory\n"
    banner += "\t\t(optional) rebuild\n"
    banner += "\t\t\tdoes a cleanall followed by a build\n"
    banner += "\t\t(optional) extrainfo\n"
    banner += "\t\t\tprints out extra debugging ouput related to the build system\n"
    banner += "\n"
    banner += "\tAnything that comes after the specials is passed verbatim to the make system and is interpreted by it.\n"
    banner += "\tSee mdMake.common for which variables the make system uses\n"
    banner += "\n"

    puts banner

    exit 2
end

#
# hack to extend String class with colors
#
class String
    def colorize(color_code)
        "\e[#{color_code}m#{self}\e[0m"
    end

    def red
        colorize(31)
    end

    def light_red
        colorize(91)
    end

    def green
        colorize(32)
    end

    def yellow
        colorize(33)
    end

    def blue
        colorize(34)
    end

    def pink
        colorize(35)
    end

    def light_blue
        colorize(36)
    end
end

#
# helper class to keep track of paths
#
class Path
    #
    # init path to some root directory
    #
    def initialize(root)
        set(root)
    end

    #
    # helper function to make printing easier (#{path} will now work)
    #
    def to_s
        @path
    end

    #
    # sets the path to the specified directory
    #
    def set(dir)
        # trailing '/' required
        if (dir[-1] != '/') then dir += '/' end

        # internal representation of the path is a string
        @path = dir

        # depth keeps track of how far back we can pop if necessary
        @depth = 0

        index = dir.index(/\//)

        while (index != nil)
            dir = dir[index+1..-1]
            @depth += 1
            index = dir.index(/\//)
        end

        @depth -= 1
    end

    #
    # "permanent" push.  that is, this will affect the internal representation of the path by appending the supplied path.
    # if a relative path is supplied (starts with "../", then the internal path will be popped before appending occurs.
    #
    def push!(dir)
        # check if absolute path and call set if necessary
        if (dir[0] == '/')
            set(dir)
            return 0
        end

        # trailing '/' required
        if (dir[-1] != '/') then dir += '/' end

        count = 0

        # remove leading "./"'s and "../"'s from dir.
        # if "../" is present, then we will need to pop from the current path the correct number of times.
        if (@path.length > 0)
            while (dir[0] == '.')
                if (dir[0...2] == "./")
                    dir = dir[2..-1]
                elsif (dir[0...3] == "../")
                    count += 1
                    dir = dir[3..-1]
                end

            end
        end

        # removing trailing directories from current path
        if (count > 0)
            if (count > @depth)
                return nil
            else
                (0...count).each do 
                    pop!
                end
            end
        end

        # append to the current path
        @path += dir
        @depth += 1

        return 0
    end

    #
    # "non-permanent" push.  that is, this will return what the effect of a "permanent" push would be, without actually doing it.
    #
    def push(dir)
        if (dir[-1] != '/') then dir += '/' end

        # if absolute path, then just return it
        if (dir[0] == '/') then return dir end

        count = 0
        path = @path

        # remove leading "./"'s and "../"'s from dir.
        # if "../" is present, then we will need to pop from the current path the correct number of times.
        if (path.length > 0)
            while (dir[0] == '.')
                if (dir[0...2] == "./")
                    dir = dir[2..-1]
                elsif (dir[0...3] == "../")
                    count += 1
                    dir = dir[3..-1]
                end

            end
        end

        # removing trailing directories from current path
        if (count > 0)
            (0...count).each do 
                path = pop(path)
            end
        end

        # append to the path
        path += dir

        return path
    end

    #
    # "permanent" pop.  that is, this will affect the internal representation of the path by removing the last trailing directory.
    #
    def pop!()
        # don't pop if nothing left
        if (@depth == 0)
            return nil
        end

        index = 0

        # find the index into the string of the last '/' character
        if (@path[-1] == '/')
            index = @path[0..-2].rindex(/\//)
        else
            index = @path.rindex(/\//)
        end

        # if no '/' character found, then remove the whole path
        if (index == nil)
            @path = ""
            @depth = 0
        # else "pop" off the trailing subdirectory by slicing it from the string
        else
            @path = @path[0..index]
            @depth -= 1
        end

        return 0
    end

    #
    # "non-permanent" pop.  that is, this will return the effect removing the last trailing directory without actually doing it.
    #
    def pop(path)
        index = 0

        # find the index into the string of the last '/' character
        if (path[-1] == '/')
            index = path[0..-2].rindex(/\//)
        else
            index = path.rindex(/\//)
        end

        # if no '/' character found, then return an empty path
        if (index == nil)
            path = ""
        # else "pop" off the trailing subdirectory by slicing it from the string
        else
            path = path[0..index]
        end

        return path
    end
end

def getOutputPath(projDir)
    lastIndex = @builds[projDir][Index::OUTPUT].rindex(/\//)
    return @builds[projDir][Index::OUTPUT][0..lastIndex]
end

def getOutput(projDir)
    lastIndex = @builds[projDir][Index::OUTPUT].rindex(/\//)
    return @builds[projDir][Index::OUTPUT][lastIndex+1..-1]
end

#
# return link source and link destination directories, given project directory.  the link source
# will be the path relative to the link destination directory where the current build's output
# will be located.  the link destination is defined by the mdMake variable LINK_OUTPUT.
#
def getLinkSrcAndDst(projDir, target)
    linkSrc = ""
    linkDst = ""

    # construct relative paths from build output to link output
    if (@builds[projDir][Index::LINKDST].length > 0)
        linkDst = @builds[projDir][Index::LINKDST]
        outDir = @builds[projDir][Index::OUTDIR] + getOutputPath(projDir)

        # get absolute path for output directory
        outPath = Path.new(projDir)
        outPath.push!(outDir)

        linkSrc = outPath.to_s + getOutput(projDir)
    end

    return linkSrc,linkDst
end

#
# search for Makefile in the supplied path for a variable defined by "name".  if isDir is true, then
# the function assumes that any string(s) it finds are to be interpreted as directories.
#
def getMakeListVariable(path, name, isDir)
    values = []
    enable = false

    if (File.exist?("#{path}mdMake") == false)
        puts "error: could not open #{path}mdMake".light_red
        exit 1
    end

    File.open("#{path}mdMake", "r").each_line do |line|
        if ((line =~ /^(\s)*#/) == nil)
            if (line =~ /^(\s)*\b#{name}\b/)
                value = line.split(":=")[1].strip
                vals = value.split(' ')
                vals.each do |v|
                    if (v != "\\")
                        if (v[-1] == '\\')
                            enable = true
                            v = v[0..-2].strip
                            if (v[-1] != '/' && isDir) then v += '/' end
                            values << v
                        else
                            if (v[-1] != '/' && isDir) then v += '/' end
                            values << v
                        end
                    else
                        enable = true
                    end
                end
            elsif (enable == true)
                value = line.strip
                vals = value.split(' ')
                vals.each_with_index do |v,i|
                    if (v[-1] != '\\' && vals.length == (i + 1))
                        enable = false
                    end
                    
                    if (v[-1] != '\\')
                        v = v[0..-1].strip
                        if (v[-1] != '/' && isDir) then v += '/' end
                        values << v
                    end
                end
            end
        end
    end
    
    if (values.length > 0)
        return values
    else
        return nil
    end
end

#
# list of dependencies found by recursively searching through Makefiles.  dependencies are stored as directory names.
# each entry is of the form "project_dir => [list of directories on which the project depends],
# e.g. "./proj1"=>["./proj2","./proj3"].
@deps = {}

#
# list of projects that need to be built.  each entry has the form "project_dir => [true|false,name of output file],
# e.g. "proj1"=>[false,"../codeLibrary.a"].  the first entry in the list is a boolean value that indicates whether or
# not the project has already been built.  the second entry is the name of the output file the project creates.
#
@builds = {}

#
# command line arguments supplied to this build script
#
@args = ""

#
# value of "TARGETS" command line option.  right now only "debug", "release", and "optdebug" are supported.
#
@targets = []

#
# flag that controls TTY output of mdMake.rb itself
#
@extrainfo = false

#
# given the full path name of a build target, this returns just the name of the library/executable/etc...
#
def getSimpleBuildName(fullName)
    # find the index into the string of the last '/' character
    index = fullName.rindex(/\//)
    if (index == nil)
        return ""
    end
    return fullName[(index +1 )..-1]
end

#
# "visits" the supplied path by parsing its Makefile for several values and storing the results inside
# of the @deps list.  it returns the dependencies of the Makefile as well as its output file (including path).
#
def visitPath(path, target, parentName)
    # find this Makefile's dependencies
    deps = getMakeListVariable(path, "DEPENDENCIES", true)
    # find this Makefile's project name (the name of the file it will output)
    name = ""
    n = getMakeListVariable(path, "NAME", false)
    if (n != nil) then name = n[0].to_s end
    # find this Makefile's output directory
    outDir = ""
    od = getMakeListVariable(path, "OUT_DIR", true)
    if (od != nil) then outDir = od[0].to_s end
    # find this Makefile's link output directory
    linkDst = ""
    ld = getMakeListVariable(path, "OUTPUT_LINK", true)
    if (ld != nil && ld.length > 0)
        ldp = Path.new(path.to_s)
        ldp.push!(ld[0].to_s)
        linkDst = ldp.to_s
    end

    output = ""

    # construct the output's path with filename
    if (name != nil && outDir != nil)
        output = "#{target}/#{name}"
    end

    if (deps == nil)
        @deps[path.to_s] = []
        return nil,outDir,output,linkDst
    end

    adjustedDeps = []

    # a project's dependency directories should always be supplied as relative to the project,
    # so we need to convert the relative paths to absolute paths relative to the root project directory
    deps.each do |d|
        # get the result of what the push would be, without messing with the current path (this does
        # the aforementioned conversion)
        newPath = path.push(d)
        adjustedDeps << newPath
    end

    # store the dependencies
    @deps[path.to_s] = adjustedDeps

    return adjustedDeps,outDir,output,linkDst
end

#
# builds the dependency list relative the specified root path
#
def getDependencies(path, target)
    # queue used to do a breadth first search of the "build tree" (it is really just a list)
    dirs = []

    # add root path and mark it as un-built for now
    dirs << path.to_s
    @builds[path.to_s] = [false, "", "", "", ""]

    # find this Makefile's project name (the name of the file it will output)
    parentName = ""
    n = getMakeListVariable(path, "NAME", false)
    if (n != nil) then parentName = n[0].to_s end

    # loop that performs the breadth first search
    while (dirs.empty? == false)
        # remove the leading entry
        dir = dirs.shift

        # if we have not yet built this project...
        if (@builds[dir][Index::BUILDFLAG] == false)
            # construct a new path based on the current dir
            p = Path.new(dir)
            # visit the new path to build its dependency list and output
            deps,outDir,output,linkDst = visitPath(p, target, parentName)

            # add it to the build list
            @builds[dir] = [false, outDir, output, linkDst]

            # if this project has dependencies, then add those as well
            if (deps != nil)
                deps.each do |d|
                    # trailing '/' required
                    if (d[-1] != '/') then d += '/' end
                    # don't include a project more than once in the build list
                    if (dirs.include?(d) == false)
                        dirs << d
                        @builds[d] = [false, "", "", ""]
                    end
                end
            end
        end
    end
end

#
# as a final step, build the root project after all the dependency projects have been built
#
def buildRootProj(root, target)
    File.open("#{root}mdMake", "r").each_line do |line|
        if ((line =~ /^(\s)*#/) == nil)
            # this line indicates that the root project is something that actually needs to be built.
            # if this line does not exist, then the root Makefile is merely a file that gives us a list
            # of other projects to build via its DEPENDENCIES variable
            if (line =~ /-include.*mdMake.common/)
                # deps is a string that will store the names of all of the root project's dependencies
                # to be passed to the make command
                deps = "\""

                # build up the deps string
                @deps[root.to_s].each do |d|
                    p = Path.new(d)
                    # chop is there to remove trailing '/'
                    deps += p.push(@builds[d][Index::OUTDIR] + @builds[d][Index::OUTPUT]).chop! + " "
                end

                if (deps.length > 1)
                    # chop trailing space
                    deps.chop!
                end
                deps += "\""

                # finally, build the root project
                name = getMakeListVariable(root, "NAME", false)
                if (name != nil && name.length > 0)
                    build(root.to_s, deps, target)
                end
            end
        end
    end
end

#
# build the project that lives in the specified directory.  if the project has dependencies, then
# this function will be called recursively to build those first.
#
def recursiveBuild(dir, target)
    if (@builds[dir][Index::BUILDFLAG] == false)
        # deps is a string that will store the names of all of the root project's dependencies
        # to be passed to the make command
        deps = "\""

        # for each of this project's dependencies, recursively call this function
        @deps[dir].each do |d|
            if (@builds[d][Index::BUILDFLAG] == false)
                recursiveBuild(d, target)
            end

            # build up the deps string
            p = Path.new(d)
            # chop is there to remove trailing '/'
            deps += p.push(@builds[d][Index::OUTDIR] + @builds[d][Index::OUTPUT]).chop! + " "
        end

        if (deps.length > 1)
            # chop trailing space
            deps.chop!
        end
        deps += "\""

        # once all the dependencies have been built, build this project
        build(dir, deps, target)
    end
end

def recursiveClean(dir, target)
    @deps[dir].each do |d|
        recursiveClean(d, target)
    end

    if (@builds[dir][Index::BUILDFLAG] == false)
        # clean the target project
        clean(dir, target)

        # mark the project as built temporarily to make sure we only clean the project once
        @builds[dir][Index::BUILDFLAG] = true
    end
end

def clean(dir, target)
    projDir = dir.to_s
    linkSrc,linkDst = getLinkSrcAndDst(projDir, target)

    # construct make command
    buildStr = "make --no-print-directory --directory=#{dir} -f mdMake TARGET=#{target} LINK_SRC=#{linkSrc} LINK_DST=#{linkDst} clean" + @args

    # do the system call to "make"
    if (@extrainfo == true) then puts buildStr end
    puts "----------------------------------------------------------------"
    puts "cleaning #{target} #{getSimpleBuildName(@builds[projDir][Index::OUTPUT])}".green
    puts "----------------------------------------------------------------"
    if (system("#{buildStr}") == false) then exit 1 end
end

#
# performs the actual build by calling "make"
#
def build(dir, deps, target)
    projDir = dir.to_s
    linkSrc,linkDst = getLinkSrcAndDst(projDir, target)

    # construct make command
    buildStr = "make --no-print-directory --directory=#{dir} -f mdMake TARGET=#{target} DEPENDENCIES=#{deps} LINK_SRC=#{linkSrc} LINK_DST=#{linkDst}" + @args

    # do the system call to "make"
    if (@extrainfo == true) then puts buildStr end
    puts "----------------------------------------------------------------"
    puts "building #{target} #{getSimpleBuildName(@builds[projDir][Index::OUTPUT])}".green
    puts "----------------------------------------------------------------"
    if (system("#{buildStr}") == false) then exit 1 end

    # mark the project as built
    @builds[dir][Index::BUILDFLAG] = true
end

#
# starting function
#
def main()
    # the root project is assumed the be the current directory unless told otherwise
    buildRoot = "."
    cleandeps = false
    clean = false
    rebuild = false

    puts ""

    # if a root directory is supplied then account for it
    if (ARGV[0] != nil && Dir.exist?(ARGV[0]))
        ARGV.[](1..-1).each do |a|
            @args += " #{a.to_s}"
            # look for "TARGETS" command line argument and store its value
            if (a.to_s =~ /\bTARGETS/)
                targetsStr = a.to_s.split("=")[1]
                @targets = targetsStr.split(",")
            end

            if (a.to_s =~ /\bextrainfo\b/)
                @extrainfo = true
            end

            if (a.to_s =~ /\bcleandeps\b/)
                cleandeps = true
                @args.gsub!(/\bcleandeps\b/, "")
            elsif (a.to_s =~ /\bclean\b/)
                clean = true
                @args.gsub!(/\bclean\b/, "")
            elsif (a.to_s =~ /\bcleanall\b/)
                cleandeps = true
                clean = true
                @args.gsub!(/\bcleanall\b/, "")
            elsif (a.to_s =~ /\brebuild\b/)
                rebuild = true
                @args.gsub!(/\brebuild\b/, "")
            end
        end

        buildRoot = ARGV[0]
    # else no root directory
    else
        ARGV.each do |a|
            @args += " #{a.to_s}"
            # look for "TARGETS" command line argument and store its value
            if (a.to_s =~ /\bTARGETS\b/)
                targetsStr = a.to_s.split("=")[1]
                @targets = targetsStr.split(",")
            end

            if (a.to_s =~ /\bextrainfo\b/)
                @extrainfo = true
            end

            if (a.to_s =~ /\bcleandeps\b/)
                cleandeps = true
                @args.gsub!(/\bcleandeps\b/, "")
            elsif (a.to_s =~ /\bclean\b/)
                clean = true
                @args.gsub!(/\bclean\b/, "")
            elsif (a.to_s =~ /\bcleanall\b/)
                cleandeps = true
                clean = true
                @args.gsub!(/\bcleanall\b/, "")
            elsif (a.to_s =~ /\brebuild\b/)
                rebuild = true
                cleandeps = false
                clean = false
                @args.gsub!(/\brebuild\b/, "")
            end
        end
    end

    if (@targets.length == 0)
        puts "warning: missing required TARGETS argument, defaulting to optdebug build".yellow
        puts ""
        @targets.push("optdebug")
    else
        @targets.each do |t|
            if (t != "debug" && t != "release" && t != "optdebug")
                puts "error: unknown target type \"#{t}\"".light_red
                exit 1
            end
        end
    end

    # remove TARGETS from @args (we no longer it, and we don't want to pass it on to the mdMake files)
    @args.gsub!(/\bTARGETS=[a-zA-Z,]+\s+/, "")

    # remove extrainfo flag from @args
    @args.gsub!(/\bextrainfo\b/, "")

    if (rebuild == true)
        @targets.each do |target|
            # change directory to specified root path
            Dir.chdir(buildRoot)
            # store current directory in helper Path class
            p = Path.new(Dir.pwd)

            # create dependency and build lists
            getDependencies(p, target)

            # for each dependant project, clean it
            @deps.each_key do |key|
                @deps[key].each do |val|
                    recursiveClean(val, target)
                end
            end

            # clean root project
            name = getMakeListVariable(p, "NAME", false)
            if (name != nil && name.length > 0)
                clean(p, target)
            end

            # reset build flags, since performing a "clean" sets them to true
            @builds.each_key do |key|
                @builds[key][Index::BUILDFLAG] = false
            end
        end
    end

    @targets.each do |target|
        # change directory to specified root path
        Dir.chdir(buildRoot)
        # store current directory in helper Path class
        p = Path.new(Dir.pwd)

        # create dependency and build lists
        getDependencies(p, target)

        if (@extrainfo == true)
            puts ""
            puts "deps: #{@deps}"
            puts ""
            puts "builds: #{@builds}"
            puts ""
        end

        if (cleandeps == true || clean == true)
            # for each dependant project, clean it
            if (cleandeps == true)
                @deps.each_key do |key|
                    @deps[key].each do |val|
                        recursiveClean(val, target)
                    end
                end
            end

            # clean root project
            if (clean == true)
                name = getMakeListVariable(p, "NAME", false)
                if (name != nil && name.length > 0)
                    clean(p, target)
                end
            end
        else
            # for each dependant project, build it
            @deps.each_key do |key|
                @deps[key].each do |val|
                    recursiveBuild(val, target)
                end
            end

            # finally, build the root project
            buildRootProj(p, target)
        end
    end

    puts "Build complete!\n\n"
end

# call starting function
main()
