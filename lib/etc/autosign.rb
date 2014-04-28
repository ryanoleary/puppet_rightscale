#! /usr/bin/env ruby

# License
#
# Copyright 2014 Nextdoor.com, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# Documentation
#
# This script provides policy based certificate auto-signing for Puppet with
# RightScale integration.  It's intended for use as a custom policy
# executable, which your Puppet master will call upon every certificate
# signing request. When this script exists with 0 status, the we tell Puppet
# to sign the certificate.  When the script exit with a non-zero status, such
# as 1, we tell Puppet not to sign the certificate.
#
# Puppet clients must be populated with special data prior to the CSR
# generation and Chef can be used to bootstrap.  See this repo for examples:
#
# https://github.com/Nextdoor/public_cookbooks/tree/master/nd-puppet
#
# Also see the Puppet documentation for more information on configuring your
# Puppet master and clients:
#
# http://bit.ly/1fGkhPW
# http://bit.ly/1gTaXw9
#
# This script requires a configuration file:
#
#   /etc/puppet/rightscale.conf
#
# You must specify a challange password and one or more account sections with
# RightScale credentials.
#
# You must also specify a custom RightScale tag in the global section which we
# use to search for and validate the instace with RightScale.  Please note,
# RightScale tags follow the format 'namespace:predicate=value'.  We
# recommend you assign this tag to new instances and set it to a unique and
# random value.
#
# You can optionally enable logging with the debug option, which accepts a
# filename as a parameter.
#
# Here's an example configuration file that has two RightScale account
# identifiers, 1234 and 5678:

#  [global]
#  challange_password = '...'
#  tag = 'namespace:predicate'
#  debug = /path/to/debug.log
#
#  [1234]
#  rightscale_email = '...'
#  rightscale_password = '...'
#
#  [5678]
#  rightscale_email = '...'
#  rightscale_password = '...'


require 'rubygems'
require 'logger'
require 'openssl'
require 'parseconfig'
require 'right_api_client'


# Static
CONF_FILE = '/etc/puppet/rightscale.conf'


def debug(config, var_name, val)
  if config['global']['debug']
    log = Logger.new(config['global']['debug'])
    log.debug '%s : %s' % [var_name, val]
    log.close()
  end
end


def signing_failed(config)
  debug(config, 'status', 'Not signing this request')
  exit 1
end


def get_rs_instance(config, account_id, pp_preshared_key)
  client = RightApi::Client.new(
             :email       => config[account_id]['rightscale_email'],
             :password    => config[account_id]['rightscale_password'],
             :account_id  => account_id)
  return client.tags.by_tag(
           :resource_type => 'instances',
           :tags          => ["%s=%s" % [config['global']['tag'],
                                         pp_preshared_key]])
end


def find_preshared_key(attributes)
  # Loop through the attributes looking for our extension
  attributes.value.value.first.value.each do |extension|
    key = extension.value[0].value
    val = extension.value[1].value

    if key == '1.3.6.1.4.1.34380.1.1.4'
      return val
    end
  end
end


def get_and_check_config(args)
  # RightScale credentials
  if File.exist?(CONF_FILE)
    config = ParseConfig.new(CONF_FILE)
  else
    # Without a config file, we don't know where to log
    # So this is printed to the console
    puts "Error: %s doesn't exist - failing autosign" % CONF_FILE
    exit 1
  end

  # Basic usage instructions - Puppet should passs the hostname as the first arg
  if args.length == 1
      hostname = args.first
  else
    debug(config, 'status', 'Usage: echo <CSR> | $0 <client hostname>')
    signing_failed(config)
  end

  # Initialize logging
  debug(config, 'status', 'Starting certificate signing for %s' % hostname)

  # Basic config sanity check
  if not config.groups.include? 'global'
    debug(config, 'status', 'The config file must have a global section')
    signing_failed(config)
  end

  if config.groups.length < 2
    debug(config, 'status',
          'The config file must contain at least one account stanza')
    signing_failed(config)
  end

  if not config['global'].include? 'challange_password' or \
    not config['global'].include? 'tag'
    debug(config, 'status',
          'The config file must have a challange_password and tag specified')
    signing_failed(config)
  end

  return config
end


def get_and_check_csr(config)
  # Read and parse the CSR from standard input
  csr = OpenSSL::X509::Request.new STDIN.read
  debug(config, :csr, csr)

  # Basic CSR sanity check
  if csr.attributes.length != 2
    debug(config, 'status', 'The CSR is missing attributes')
    signing_failed(config)
  end

  # Extract attributes from the CSR
  challange_password = csr.attributes[0].value.value.first.value
  debug(config, :challange_password, challange_password)

  pp_preshared_key = find_preshared_key(csr.attributes[1])
  debug(config, :pp_preshared_key, pp_preshared_key)

  return challange_password, pp_preshared_key
end


def validate_request(config, challange_password, pp_preshared_key)
  instances = []
  for account_id in config.get_groups()
    if account_id != 'global'
      instances += get_rs_instance(config, account_id, pp_preshared_key)
    end
  end

  # Tell Puppet to sign the request if our criteria are met
  if config['global']['challange_password'] == challange_password and \
    instances.length == 1
    debug(config, 'instance uid', instances[0].show.resource.show.resource_uid)
    debug(config, 'status', 'Signing this request')
    exit 0
  end

  debug(config, :instances, instances)
  signing_failed(config)
end


if __FILE__ == $0
  begin
    config = get_and_check_config(ARGV)
    challange_password, pp_preshared_key = get_and_check_csr(config)
    validate_request(config, challange_password, pp_preshared_key)
  rescue => exception
    debug(config, :exception, exception)
    debug(config, :exception, exception.inspect)
    debug(config, :exception, exception.backtrace)
    signing_failed(config)
  end
end

signing_failed(config)
