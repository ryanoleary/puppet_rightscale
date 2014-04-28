require 'fileutils'
require 'rubygems'
require 'rake'
require 'puppet-lint/tasks/puppet-lint'
require 'puppetlabs_spec_helper/rake_tasks'
require 'yaml'

# Puppet-lint Rake Specific settings
PuppetLint.configuration.send("disable_80chars")
PuppetLint.configuration.send("disable_class_parameter_defaults")
PuppetLint.configuration.with_context = true
PuppetLint.configuration.fail_on_warnings = true

#
# Individual puppet module rspec testing.
#
# NOTE: Excludes tests on vendor-supplied modules in the /vendor/ path
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = FileList['spec/**/*_spec.rb']
  t.rspec_opts = "--format d --color"
end

# Running just 'rake' calls all of our default actions
task :default => [:lint]
task :default => [:spec]
