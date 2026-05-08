require "bundler/setup"
require "standard/rake"

require "rake/extensiontask"
Rake::ExtensionTask.new("activesupport_json_escape") do |ext|
  ext.lib_dir = "lib/activesupport_json_escape"
end

require "minitest/test_task"
Minitest::TestTask.create

require "ruby_memcheck"
namespace :test do
  RubyMemcheck::TestTask.new(valgrind: [:clobber, :compile])
end

task default: [:clobber, :compile, :test, :standard]
