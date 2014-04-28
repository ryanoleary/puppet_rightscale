require 'rubygems'
require 'pathname'
require 'puppetlabs_spec_helper/module_spec_helper'

proj_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))

RSpec.configure do |c|
  c.module_path = 'spec/modules'
  c.manifest_dir = 'spec/manifests'

  # Find the Hiera fixtures used to mocking hiera data for unit tests.
  c.hiera_config = './hiera.yaml'
end

# Load up the scenarios.yml file and create hashes both referneced by
# string as well as symbols. Default to the BY_SYMBOL hash
DEFAULT_FACTS_BY_STRING = YAML.load(File.read("scenarios.yml"))['__default_facts']
DEFAULT_FACTS_BY_SYMBOL = Hash[DEFAULT_FACTS_BY_STRING.map{|(k,v)| [k.to_sym,v]}]

# RSPEC Tests do not properly load up the site.pp file, so the facts generated
# in that file are not available to the puppet manifests. We append some facts here
# specifically for RSPEC tests only. They cannot be added to the scenarios.yml
# file because the Puppet Catalog Compile tests DO take into account the site.pp,
# causing errors.
RSPEC_DEFAULT_FACTS = DEFAULT_FACTS_BY_SYMBOL
RSPEC_DEFAULT_FACTS[:mem] = 17179869184
RSPEC_DEFAULT_FACTS[:mem_mb] = 16384

# Generate coverage reports for untested Puppet modules:
# http://www.morethanseven.net/2014/01/25/code-coverage-for-puppet-modules/
#at_exit { RSpec::Puppet::Coverage.report! }
