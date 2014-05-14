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
# This provider for the rs_tag puppet resource type leverages the built-in
# '/usr/bin/rs_tag' command installed by the RightLink agent on all
# RightScale managed hosts.
#
# For performance reasons, this code follows the provider prefetch model
# described here:
#
#   http://garylarizza.com/blog/2013/12/15/seriously-what-is-this-provider-doing/
#
# When the Puppet client agent  loads up, it calls the class method 'prefetch'
# which triggers the 'instances' class method. This method calls 'rs_tag' once
# to get a list of all of the existing tags and pre-geerate resources for each
# of them. Puppet then uses this list of known resources to decide whether or
# not to call the create/destroy methods for the provider.

require 'rubygems'
require 'json'

Puppet::Type.type(:rs_tag).provide(:ruby) do
  desc "Manage RightScale tags for a server"
  commands :rs_tag => 'rs_tag'

  mk_resource_methods

  ##############################################################################
  # Class Methods
  ##############################################################################

  # Fetch all of our tags and pre-populate resource objects for each one
  # so that puppet knows which tags are already set.
  def self.get_tags()
    tag_properties = {}

    begin
      output = rs_tag(['--list', '--format', 'json'])
    rescue Puppet::ExecutionFailure => e
      Puppet.debug("Rs_tag execution had an error (skipping) -> #{e.inspect}")
      return nil
    end

    begin
      tags = JSON.parse(output)
    rescue JSON::ParserError => e
      Puppet.debug("Parsing rs_tag output had an error -> #{e.inspect}")
      return nil
    end

    # Log out the tags, then return them
    Puppet.debug("Got tags #{tags.join(', ')}")

    # Dump all the tags into a hash
    providers = []
    tags.each do |tag|
      # Create a new fresh properties hash
      properties = {}

      # Split our tag into a name/value
      n, *v = tag.split('=')

      # Now populate some instance properties about the state of this tag
      properties[:ensure]   = :present
      properties[:value]    = v.join('=')
      properties[:provider] = :ruby
      properties[:name]     = n

      # Log out out and then generate a new instance with the properties
      Puppet.debug("Tag properties: #{properties.inspect}")
      providers << new(properties)
    end
    providers
  end

  # This method is called by Puppet internally to get an array of existing
  # tags on a host in Resource form. This method is primarily called by the
  # prefetch() method below. See the blog post listed in the doc header for
  # more information.
  def self.instances
    self.get_tags()
  end

  # This method is called by the Puppet agent before any changes to Rs_tag[]
  # resources are applied. Having this method allows Puppet to do a one-time
  # request for all the existing tag resources, pre-populate the current status
  # of each resource in an object. This prevents multiple calls out to the
  # `rs_tag` executable.
  def self.prefetch(resources)
    i = instances
    return nil if not i

    i.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  ##############################################################################
  # Public Methods
  ##############################################################################

  # Combine a resource name and value together to create a full tag
  def generate_tag(name, value)
    # If no value supplied, just return the name as is.
    return name if not value

    # Join the values and return
    return "#{name}=#{value}"
  end

  ##############################################################################
  # Special methods called by Puppet
  ##############################################################################

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    tag = generate_tag(resource[:name], resource[:value])
    Puppet.debug("Create tag: #{tag}")
    rs_tag(['--add', tag])
  end

  def destroy
    tag = generate_tag(resource[:name], resource[:value])
    Puppet.debug("Destroy tag: #{tag}")
    rs_tag(['--remove', tag])
  end

  # Updating the 'value' of a tag is no different than creating a new tag,
  # so we just call the create() method.
  def value=(value)
    create()
  end
end
