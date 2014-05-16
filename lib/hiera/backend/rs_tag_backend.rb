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
#
# ## Documentation
#
# This is a support module -- the main usage documentation is inside the
# modules README file.
#
# ## Authors
#
# Matt Wise <matt@nextdoor.com>
#

require 'rubygems'
require 'logging'
require File.join(File.dirname(__FILE__), '..', '..', 'rightscale.rb')

# This is a custom logging hack that allows us to take the Logging
# objects and append their messages through the Puppet logging
# framework.
class PuppetLogger < ::Logging::Appender
  def write(message)
    Puppet.debug("#{message.logger}: #{message.data}")
  end
end


class Hiera
  module Backend
    class Rs_tag_backend
      # This method initializes the backend once, and creates the common
      # RightScale connection object. This means that we create one object
      # and reuse it multiple times throughout the puppet runs -- which cuts
      # down on individual login attepts against the API.
      def initialize
        # Redirect logging messages through our custom PuppetLogger appender
        # that sends the messages through Puppet.debug.
        Logging.logger.root.add_appenders(PuppetLogger.new('rs_tag_backend'))
        Logging.logger.root.level = :debug

        # Begin initializing the RightScale object
        @rs = RightScale.new()

        # Initialize a local hash that we'll use to cache objects temporarily
        @cache = Hash.new()

        # Done!
        debug("Hiera Backend Initialized")
      end

      # Accessor method for the [:rightscale][:tag_prefix] config option
      # so that its easier to mock in the unit tests. See the spec file
      # for details on WHY this is necessary.
      def prefix
        Config[:rightscale][:tag_prefix]
      end

      # Accessor method for the [:rightscale][:cache_timeout] config option
      # so that its easier to mock in the unit tests. See the spec file
      # for details on WHY this is necessary.
      def cache_timeout
        Config[:rightscale][:cache_timeout]
      end

      # Quick logger method that writes out a common logging line with the
      # [rs_tag-backend] prefix.
      #
      # @param msg [String]  The message to log out.
      #
      def debug(msg)
        Hiera.debug("[rs_tag_backend] #{msg}")
      end

      # The lookup function is the most important part of a custom backend.
      # The lookup function takes four arguments which are:
      #
      # @param key [String]             The lookup key specified by the user
      #
      # @param scope [Hash]             The variable scope. Contains fact
      #                                 values and all other variables in
      #                                 scope when the hiera() function was
      #                                 called. Most backends will not make
      #                                 use of this data directly, but it will
      #                                 need to be passed in to a variety of
      #                                 available utility methods within Hiera.
      #
      # @param order_override [String]  Like scope, a parameter that is
      #                                 primarily simply passed through
      #                                 to Hiera utility methods.
      #
      # @param resolution_type [Symbol] Hiera's default lookup method is
      #                                 :priority, in which the first value
      #                                 found in the hierarchy should be
      #                                 returned as the answer.
      #
      def lookup(key, scope, order_override, resolution_type)
        # Set the default answer. Returning nil from the lookup() method
        # indicates that no value was found. In this example hiera backend,
        # we start by assuming no match, and will then try to find a match at
        # each level of the hierarchy. If by the time we complete our
        # traversal of the hierarchy and have not found an answer, then this
        # default value of nil will be returned.
        answer = nil

        # Sanity  check, submitting a nil tag should quickly return nil
        return answer if key == nil

        # If the supplied key does not match the configured prefix, then
        # we immediately bail out so no REST calls are made.
        return answer if not key =~ /^#{prefix}/

        # Go ahead, the prefix matched our supplied key.
        #
        # Note: Most Hiera backends are given a hiearachy of potential
        #       datasources, and then you iterate over them to get the results
        #       back. This module does *not* do that. We use a single
        #       RightScale object to search for all of the values associated
        #       with the supplied tag, and return the entire list.
        #
        debug("Looking up '#{key}', resolution type is '#{resolution_type}'")
        answer = search(key)

        debug("Returning values: #{answer.inspect}")
        return answer
      end

      # Calls out to the RightScale client and requests a list of unique, full
      # tags. The value for each tag is then parsed out and returned as a list
      # of unique values.
      #
      # @param key [String] The string prefix of the tag to search for. Can
      #                     either be the 'namespace', 'namespace:prefix'
      #                     or 'namespace:prefix=value' (though the last one
      #                     isn't terribly useful).
      #
      def search(key)
        # Return the value from our cache if its there
        cached_results = get_from_cache(key)
        return cached_results if cached_results
        debug("Not found in cache, requesting #{key} from RightScale")

        # Call out with the supplied tag and try to get results back
        results = @rs.get_tags_by_tag(key)
        debug("Returned results: #{results.inspect}")

        # Now, walk through the results and simply get back the actual
        # values (from namespace:predicate=value) that were returned.
        values = []
        results.each do |elem|
          values << elem.split('=')[1]
        end

        # Now return the values (and store them in the cache). Only store
        # them in the cache if the cache_timeout is actually set.
        if cache_timeout
          @cache[key] = {
            :timestamp => Time.now.to_i,
            :values    => values,
          }
        end

        return values
      end

      # Checks the local instance cache to see if a particular key is already
      # stored or not. If it is, and if the timestamp is still valid (not
      # expired) then it returns that key values.
      #
      # @param key [String] The string name of the key that we're searching
      #                     for in our cache.
      #
      def get_from_cache(key)
        # Return quickly if the key is not in the cache at all
        return false if not @cache.has_key?(key)

        # Return false if something is wrong with the cached data
        # and it has no timestamp.
        return false if not @cache[key].has_key?(:timestamp)

        # Return quickly if the key is in the cache, but its expired
        delta = Time.now.to_i - @cache[key][:timestamp]
        if delta > cache_timeout
          @cache.delete(key)
          return false
        end

        # Ok, if we got here, the key is good and up to date, so return it
        debug("Returning #{key} from cache: #{@cache[key][:values]}"
        return @cache[key][:values]
      end
    end
  end
end
