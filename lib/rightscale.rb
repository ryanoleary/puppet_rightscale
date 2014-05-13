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
# Charles McLaughlin <charles@nextdoor.com>
# Matt Wise <matt@nextdoor.com>
#

require 'rubygems'
require 'logging'
require 'parseconfig'
require 'right_api_client'
require 'uri'

DEFAULT_API_URL = 'https://my.rightscale.com'

# By default, this method looks for the rightscale.conf file in the following
# filesystem locations:
#
#   /etc/puppet/rightscale.conf
#   <module path>/lib/etc/rightscale.conf
#
POTENTIAL_CONFIGS = [
  # Suggested global configuration path
  "/etc/puppet/rightscale.conf",

  # Module-specific configuration path
  File.expand_path(File.join(
    File.dirname(__FILE__),
    'etc',
    'rightscale.conf'))]


# RightScale Class used for interacting with RightScale accounts
class RightScale
  def initialize()
    @log = Logging.logger[self]
    @log.info('RightScale class initializing...')
    @config = nil
  end

  # RightScale has a `get_tag_by_tag` API call that returns back a list
  # of tags that match a given wildcard expression. This is the fastest
  # way to return back alot of data at once -- but it will *not* return
  # an actual list of Instances (it actually includes their HREFs, but not
  # real instance details).
  #
  # This method expects you to supply only the tag *name* and the tag
  # *predicate*. Full name:predicate=value searches are not supported
  # in this method -- nor do they make sense, because you would get back
  # at-most one result which is exactly what you supplied.
  #
  # * Note: Duplicate tags are de-duped on a per-account level by
  #         RightScale. We further de-dupe them in this method between
  #         the two accounts.
  #
  # * *Args*    :
  #   - +tag+ -> String of the tag-name you want to search for. Eg:
  #              nd:auth, nd:service, etc.
  #              (suggest: nd:auth, then parse the results yourself)
  #   - +dedup+ -> Disable the default deduping of returned tags by
  #                setting this to false.
  #
  # * *Returns* :
  #   - An array of tags that matched the tag you supplied.
  #     (you supply 'nd:auth' and you get back: [nd:auth=prod, nd:auth=eng])
  #
  def get_tags_by_tag(tag, dedup = true)
    # Split up the tag. The namespace and predicate are used, the value
    # is thrown away (if supplied).
    namespace, predicate, value = split_tag_for_searching(tag)

    # The *include_tags_with_prefix* parameter below must be in the form
    # *namespace:prefix* (with no value). Even if prefix is empty, it still
    # must be include the ':'.
    tag_prefix = "#{namespace}:#{predicate}"

    results = []
    get_clients().each do |client|
      # Go get our list of resource_tag objects
      @log.info("Searching account #{client.account_id} for instances with tag: #{tag}")
      returned = client.tags.by_tag(
        :resource_type            => 'instances',
        :include_tags_with_prefix => tag_prefix,
        :tags                     => [ tag ])

      # Now, returned should include an array of resource_tag objects,
      # which each have a 'tags' section. Pull down the tags section, and
      # pull out all the tags.
      @log.debug("Scanning #{returned.inspect}")
      returned.each do |ret|
        @log.debug("Scanning #{ret.inspect}")
        ret.tags.each do |kv|
          @log.debug("Appending #{kv['name']}")
          results << kv['name']
        end
      end
    end

    # Return the results... deduped or not.
    sorted = results.sort
    unique = sorted.uniq
    return dedup ? unique : sorted
  end

  # Cleanly splits up a supplied tag name into its namespace, predicate
  # and values. Returns all three separately in a list.
  #
  # * *Args*    :
  #   - +tag+ -> String of the tag name
  #
  # * *Returns* :
  #   - [ <namespace>, <predicate>, <value> ]
  #
  def split_tag_for_searching(tag)
    # Prep our returns
    namespace = predicate = value = nil

    # Split the tag by the colon first
    namespace, predicate = tag.split(':')

    # If the predicate is not nil, then split it on the equals
    if predicate
      predicate, value = predicate.split('=', 2)
    end

    # Now, return the namespace, predicate and value
    elements = [ namespace, predicate, value ]
    @log.debug("Split tag #{tag} into: #{elements.inspect}")
    return elements
  end

  # Simple method to get and return the configuration file after sanity
  # checking it for valid content. If the config has been read once already,
  # it is never read again and we return the same object over and over.
  #
  # * *Args*    :
  #   - None
  #
  # * *Returns* :
  #   - A ParseConfig object thats been sanity checked
  #
  def get_config()
    # Return the config object if its already been built
    return @config if @config

    # Read RightScale credentials
    config = nil
    POTENTIAL_CONFIGS.each do |conf|
      @log.debug("Looking for config file at #{conf}")
      begin
        config = ParseConfig.new(conf)
        @log.debug("Found config file (#{conf})")
        break
      rescue Exception=>e
        # Just move on.. We will catch the error with a check below
      end
    end

    if not config
      raise("Could not find config file here: #{POTENTIAL_CONFIGS.inspect}")
    end

    # Basic config sanity check
    if not config.groups.include? 'global'
      raise("The config file must have a global section: #{config.inspect}")
    end

    if config.groups.length < 2
      raise("The config file must contain at least one account stanza: #{config.inspect}")
    end

    @config = config
  end

  # Quick method for getting a bunch of RightScale client instances for each
  # configured account in the config file. This method gets the clients once,
  # then returns the same list over and over again.
  #
  # * *Args*    :
  #   None
  #
  # * *Returns* :
  #   - array containing valid RightApi::Client Objects
  #
  def get_clients()
    return @clients if @clients

    # Get our config object
    config = get_config()

    clients = []
    get_config().get_groups().each do |id|
      if id != 'global'
        @log.debug("Creating client object for account #{id}...")
        clients << get_client(
          id,
          config[id]['email'],
          config[id]['password'],
          config[id]['oath2_token'],
          config[id]['api_url'])
        @log.debug(clients[-1].inspect)
      end
    end
    @clients = clients
  end

  # Get a single instance of a RightApi::Client basd on the supplied
  # credentials. If an oaht2_token is supplied, we go out and get a fresh
  # access token to pass in, and ignore the email/password.
  #
  # * *Args*  :
  #   - +account_id+ -> string of RightScale Account ID
  #   - +email+ -> string of RightScale Account Name
  #   - +password+ -> string of Password for above email
  #   - +oath2_token+ -> string with valid OATH2 token to use instead
  #                      of the above email/password
  #   - +api_url+ -> string of RightScale API URl Endpoint
  #
  # * *Returns* :
  #   - A RightApi::Client object fully configured
  #
  def get_client(account_id, email = nil, password = nil,
                    oath2_token = nil, api_url = nil)

    # The oath2_token setting takes precedence because its more secure
    # than passing around email/passwords (and the RightClient::API
    # object *logs* them!).
    if oath2_token
      access_token = get_access_token(oath2_token, api_url)
      email        = nil
      password     = nil
    end

    if (not email or not password) and not oath2_token
      raise("Account #{account_id} missing either email, password or oath2_token")
    end

    RightApi::Client.new(
      :account_id   => account_id,
      :email        => email,
      :password     => password,
      :access_token => access_token,
      :api_url      => api_url)
  end

  # Returns a temporary access token for RightScale by reaching out to the API
  # with the supplied oath2 API token. This returned temporary token is then
  # used by the RightAPI::Client object to access the API.
  #
  # * *Args*    :
  #   - +oath2_token+ -> string for RightScale refresh token for OAuth2
  #   - +api_url+ -> string with the API URL endpoint
  #                  (def: https://my.rightscale.com)
  #
  # * *Returns* :
  #   - string of temporary access token for RightScale
  #
  def get_access_token(oath2, api_url = DEFAULT_API_URL)
    # Generate the full API URL for getting the API Token and generate
    # the RestClient object that will be used to access it
    url = "#{api_url}/api/oauth2"

    # Put together our POST data for the token request
    post_data = Hash.new()
    post_data['grant_type'] = 'refresh_token'
    post_data['refresh_token'] = oath2

    # Actually reach out to RightScale and ask for the token back
    @log.debug("Reaching out to #{url} for a token...")
    response = RestClient.post(
      url, post_data,
      :timeout       => 15,
      :X_API_VERSION => '1.5',
      :content_type  => 'application/x-www-form-urlencoded',
      :accept        => '*/*')

    case response.code
    when 200
      data = JSON.parse(response.body)
      token = data['access_token']
      @log.info("Login success! Got access token from RightScale: #{token}")
      return token
    else
      raise('FAILED. Failed to get access token.')
    end
  end
end
