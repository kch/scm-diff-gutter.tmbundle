#!/usr/bin/env ruby
require "pathname"
require "shellwords"

# to test directly in shell without TM interaction: TM_SCM_NAME=git TM_FILEPATH=some_file diff-report.rb < some_file_changed

scm, path = ENV.values_at "TM_SCM_NAME", "TM_FILEPATH"
exit unless scm && path

GIT_CMD  = ENV.fetch "TM_GIT", "git"
HG_CMD   = ENV.fetch "TM_HG",  "hg"
DIFF_CMD = %w[ diff -u ]

Pathname.class_eval{ alias_method :to_str, :to_s } # make working with pathnames as strings a bunch easier

case scm
when "git"
  root_cmd    = "#{GIT_CMD} rev-parse --show-toplevel"
  tracked_cmd = "#{GIT_CMD} ls-files -z %s"
  cat_cmd     = "#{GIT_CMD} show :%s"
when "hg"
  root_cmd    = "#{HG_CMD} root"
  tracked_cmd = "#{HG_CMD} status -nq0 %s"
  cat_cmd     = "#{HG_CMD} cat %s"
else exit
end

path = Pathname.new(path)
path = path.realpath if path.relative? # mostly for direct testing
exit unless path.exist?

Dir.chdir path.dirname
scm_root = `#{root_cmd} 2>/dev/null`.chomp
exit unless $?.success? && !scm_root.empty?
scm_root = Pathname.new scm_root

Dir.chdir scm_root
relpath  = path.relative_path_from(scm_root).to_s
tracked  = !`#{tracked_cmd % relpath.shellescape} 2>/dev/null`.chomp.empty?
exit unless tracked && $?.success?

orig_cmd = cat_cmd % relpath.shellescape
orig_io  = IO.popen orig_cmd
diff_io  = IO.popen [*DIFF_CMD, "/dev/fd/#{orig_io.fileno}", "/dev/stdin", orig_io=>orig_io, in:STDIN]

added, changed, in_block = [], [], false

while line = diff_io.gets
  if line =~ /^@@ -(\d+),(\d+) \+(\d+),(\d+) @@/
    lineno   = $3.to_i
    deleted  = 0
    in_block = true
  elsif in_block
    if line =~/^ /
      lineno += 1
      deleted = 0
    elsif line =~/^-/
      deleted += 1
    elsif line =~/^\+/
      if deleted == 0
        added << lineno
      else
        changed << lineno
        deleted -= 1
      end
      lineno += 1
    end
  end
end

def reset_marks(path, lines, mark)
  mate = ENV["TM_MATE"]
  cmd  = mate ? [mate] : %w[ echo mate ] # if invoked from outside textmate (without TM_MATE set) just print what it would run, instead
  cmd << "--clear-mark=#{mark}"
  cmd.concat ["--set-mark=#{mark}", *lines.map{|n| "--line=#{n}" }] unless lines.empty?
  cmd << path
  system *cmd
end

reset_marks path, added,   "#{ENV["TM_BUNDLE_SUPPORT"]}/added.pdf"
reset_marks path, changed, "#{ENV["TM_BUNDLE_SUPPORT"]}/changed.pdf"
