#! /usr/bin/env ruby
# ## License
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
# ## Documentation
#
# This executable can be used to validate whether or not a server asking
# for its Puppet certificate should have it signed. Documentation for this
# script can be found in the main module README file.
#
# ## Authors
#
# Charles McLaughlin <charles@nextdoor.com>
# Matt Wise <matt@nextdoor.com>
#

require 'rubygems'
require 'logging'
require 'openssl'
require File.join(File.dirname(__FILE__), '..', 'rightscale.rb')


# Start logging to console. Will check the debug config setting and append
# logs to a log file if necessary.
Logging.logger.root.appenders = Logging.appenders.stdout
Logging.logger.root.level = :debug
@log = Logging.logger[self]

PP_PRESHARED_KEY_VALUE='1.3.6.1.4.1.34380.1.1.4'

class AutoSigner
  # Initialize the AutoSigner object by sanity checking the config, creating
  # a RightScale object, and setting up logging.
  def initialize()
    @log = Logging.logger[self]

    # Get our RightScale connection object, and our config object
    @rs     = RightScale.new()
    @config = @rs.get_config()

    # By default, log to /dev/null. If a debug log file is presented, then
    # we use that instead.
    if @config['global']['debug']
      Logging.logger.root.add_appenders(Logging.appenders.file(@config['global']['debug']))
    end

    # Sanity check that the config has the challenge_password and tag settings.
    if ( not @config['global'].include? 'challenge_password' or
         not @config['global'].include? 'tag' )
      message = ('The config file must have a challenge_password ' \
                 'and tag specified')
      raise(message)
    end

    # Initialized!
    @log.debug('Initialized!')
  end

  # Search through a supplied list of instance attributes for a CSR and
  # looks for a specific key (the Puppet preshared key attribute)
  #
  # * *Args*    :
  #   - +attributes+ -> Attributes hash from a CSR object
  #
  # * *Returns* :
  #   - The value of the attribute matching the pp_preshared_key name.
  #
  def find_preshared_key(attributes)
    # Loop through the attributes looking for our extension
    begin
      attributes.value.value.first.value.each do |extension|
        key = extension.value[0].value
        val = extension.value[1].value

        if key == PP_PRESHARED_KEY_VALUE || key == 'pp_preshared_key'
          return val
        end
      end
    rescue Exception => e
      raise("Invalid CSR: #{e}")
    end
  end

  # Validates an incoming CSR and ensures that it has both the
  # challenge_passphrase as well as the pp_preshared_key embedded
  # in the CSR attributes.
  #
  # * *Args*    :
  #   - +raw_csr+ -> The CSR in raw string format
  #
  # * *Returns* :
  #   - Nothing, just returns cleanly
  #
  # * *Raises*  :
  #   - Exception if any failure
  #
  def validate_csr(raw_csr)
    # Read in the CSR text and convert it to a CSR object
    csr = OpenSSL::X509::Request.new raw_csr
    @log.debug("CSR: #{csr}")

    # Basic CSR sanity check
    if csr.attributes.length != 2
      raise('The CSR is missing attributes')
    end

    # Extract attributes from the CSR
    challenge_password = csr.attributes[0].value.value.first.value
    pp_preshared_key = find_preshared_key(csr.attributes[1])
    @log.debug("CSR Supplied challenge_password: #{challenge_password}")
    @log.debug("CSR Supplied pp_preshared_key: #{pp_preshared_key}")

    # Lastly, if the challenge password odesnt match, bail
    if challenge_password != @config['global']['challenge_password']
      raise('The CSR has an invalid challenge_password.')
    end

    return challenge_password, pp_preshared_key
  end

  # The main method for validating that a CSR should be signed.
  #
  # * *Args*    :
  #   - +hostname+ -> String hostname that we're signing
  #   - +csr+ -> String of the raw CSR materials to check
  #
  # * *Returns* :
  #   - Returns true if signing should occur
  #
  # * *Raises* :
  #   - An Exception if signing should not occur
  #
  def validate(hostname, csr)
    # Verify that the CSR is valid first. This raises an exception if its not.
    csr_challenge_password, csr_pp_preshared_key = validate_csr(csr)

    # Now, go to RightScale and verify that there is only one server with
    # a pp_preshared_key that matches the one in this CSR. If there are more
    # or less than exactly one, fail.
    tag_name  = @config['global']['tag']
    tag_value = csr_pp_preshared_key
    expected_tag = "#{tag_name}=#{tag_value}"

    # Now go search for the tags and see how many we get back... Note we
    # explicitly turn off tag deduping so that we know if we got multiple
    # tags back that matched.
    found_tags = @rs.get_tags_by_tag(expected_tag, false)

    # If the length is not exactly 1, something bad happened.
    if not found_tags.length == 1
      raise('Either too many, or too few instances were returned: ' \
            "#{found_tags.inspect}")
    end

    # This shouldn't be possible, but just double check that the returned tag
    # matches the supplied tag.
    if found_tags[0] != expected_tag
      raise("Incorrect tag returned (#{found_tags[0]}), wanted #{expected_tag}!")
    end

    # Looks good...
    @log.info("Found matching instance, signing approved for #{hostname}.")

    # Return true
    return true
  end
end


if __FILE__ == $0
  # Basic usage instructions - Puppet should passs the hostname as the first arg
  if ARGV.length == 1
      hostname = ARGV.first
  else
    abort('Usage: echo <CSR> | $0 <client hostname>')
    signing_failed()
  end

  # Walk through the signing process. Wrap the entire thing in a rescue
  # block and appropriately fail on any raised exception.
  begin
    signer = AutoSigner.new()
    signer.validate(hostname, STDIN.read)
  rescue Exception => e
    @log.error("Error: #{e.inspect}")
    abort()
  end

  # At this point, exit cleanly
  exit(0)
end
