# RightScale Facter Plugin v2.0
#
# This plugin is designed to retrieve facts for a node that has been
# launched thorugh the RightScale cloud management platform. Several
# of these facts are gathered directly from the local files created
# by the RigthLink agent on a host. Other facts are gathered through
# the RightScale 1.5 API -- if it is available.
#
# This API is only available if your RightScale account is hosted in
# the newer UCP environments. If your access URL in RightScale is
# reached through http://my.rightsacle.com, you are on the older
# LCP system and need to migrate your account.
#
# For backwards compatibility, this plugin will fail silently if the
# 1.5 API is not available.
#
# Author: Matt Wise (matt@nextdoor.com)
#

require 'rubygems'

# Try to import the RightScale API Client Code. If its not there, quietly
# bail out.
begin
  require 'right_api_client'
rescue LoadError
  Facter.debug "The 'right_api_client' gem is missing. Please install it."
end

begin
  require 'json'
rescue LoadError
  Facter.debug "The 'json' gem is missing. Please install it."
end

# RightScale Cloud 'user-data' dictionary file location
file='/var/spool/cloud/user-data.dict'

# Quick hack on the Hash object in Ruby that allows us to 'smash' it into
# a simpler key/value list
class Hash
  def smash(prefix = nil)
    inject({}) do |acc, (k, v)|
      key = prefix.to_s + k
      if Hash === v
        acc.merge(v.smash(key + '-'))
      else
        acc.merge(key => v)
      end
    end
  end
end

# Quick "key name" sanitizer. Replaces a bunch of non-puppet-friendly
# characters with friendly ones. Slashes to dashes, etc.
def clean(key)
  key = key.gsub(/[^a-zA-Z_]/,'_')
  key = key.gsub(/[_]+/,'_')
  return key
end

# First parse in the user-data dict into key/value pairs. If this fails,
# we know the host is not a RightScale host and we can move on. These values
# effectively never change, so we can load them once here and set them.
if File.exists?(file)
  open(file).read.split("\n").each do |line|
    pair = line.split("=")
    if pair[0] =~ /^RS.*/
      Facter.add(pair[0]) { setcode { pair[1] } }
    end
  end
else
  Facter.debug "Not a RightScale host."
end

def get_client()
  # If the RightScale API has not been loaded, return nil.
  if not defined?(RightApi)
    return
  end

  # Login if this is the first time get_data() has been called. Store the
  # client in a global variable for future re-runs.
  if not $client
    begin
      creds = Facter.value('rs_api_token').split(':')
      Facter.debug("rs-facts: get_data() logging in for the first time " \
                   "to account #{creds[0]}")
      $client = RightApi::Client.new(:instance_token => creds[1],
                                     :account_id => creds[0])
    rescue Exception => e
      return
    end
  end
  return $client
end

def get_disk_cache()
  # What time is it now?
  now = Time.now.to_i

  # Create the $disk_cache object if its missing
  $disk_cache = {} if not $disk_cache

  if not File.exists?("/var/tmp/rs-facts.json")
    Facter.debug("rs-facts: get_disk_cache() json cache does not exist")
    $disk_cache['dob'] = now if not $disk_cache.has_key?('dob')
    $disk_cache['data'] = {} if not $disk_cache.has_key?('data')
    return $disk_cache
  else
    # Read settings from disk cache file
    if not $disk_cache.has_key?('dob')
      file_cache_mtime = File.mtime("/var/tmp/rs-facts.json").to_i
      Facter.debug("rs-facts: get_disk_cache() reading json cache file");
      file = File.read("/var/tmp/rs-facts.json")
      $json = JSON.parse(file);
      $disk_cache['data'] = {}
      $disk_cache['data']['links'] = $json['links']
      $disk_cache['data']['tags'] = $json['tags']
      $disk_cache['data']['instance'] = $json['instance']
      $disk_cache['data']['inputs'] = $json['inputs']
      $disk_cache['data']['cached'] = true
      $disk_cache['dob'] = file_cache_mtime
    end
  end
  return $disk_cache
end

def get_cache()
  # What time is it now?
  now = Time.now.to_i

  $disk_cache_data = get_disk_cache() if not $disk_cache_data

  # Create the $cache object if its missing
  $cache = $disk_cache_data if not $cache

  # If there is no $cache object, then create it
  $cache['data'] = {} if not $cache.has_key?('data')
  $cache['dob'] = now if not $cache.has_key?('dob')

  # If the last time we ran was more than 4 hours ago, we wipe out our
  # cache objects entirely.
  time_delta = now - $cache['dob']
  Facter.debug("rs-facts: cache age is #{time_delta}s")
  if time_delta > 14400
    Facter.debug("rs-facts: cached results have expired")
    $cache['data'] = {}
    $cache['dob'] = now
  end

  # If the last time we ran was more than 60 seconds ago, we wipe out
  # our tags cache only
  if time_delta > 60
    Facter.debug("rs-facts: cached tags results have expired")
    $cache.delete('tags')
  end  

  return $cache['data']
end

def get_data(data)
  # IF there is no RightScale client available, bail quietly.
  if not get_client()
    Facter.debug("rs-facts: No RightAPI client available.")
    return []
  end

  # Get our cache object. If its not available, a new one is created that
  # is empty, which will trigger the code blocks to fetch new data..
  cache = get_cache()

  # If the cache doesn't have all of our expected data sections re-get it
  if not cache.has_key?('instance')
    Facter.debug("rs-facts: refetching data...")
    # Get our instance data object... we'll walk through it below.
    instance = get_client().get_instance() if not instance

    # Gather the standard 'instance' data and store all of the string values
    # returned. Ignore all of the key/value pairs where the value is not
    # a string or an array of strings.
    #
    # (this effectively ignores keys where the value is an array of hashes,
    #  those need to he handled separately below)
    cache['instance'] = {}
    instance.raw.smash('rs_').each do |k,v|
      # Clean the key-name
      k = clean(k)

      # If its a basic string, store it
      cache['instance'][k] = v if v.is_a? String

      # Now, look for any key/value pair where the value is an Array,
      # then walk through that array and add each key/value pair.
      if v.is_a? Array
        v.each_with_index do |v,x|
          k = "#{k}_#{x}"
          cache['instance'][k] = v if v.is_a? String
        end
      end
    end
  end

  if not cache.has_key?('inputs')
    Facter.debug('rs-facts: fetching inputs...')
    # Get our instance data object... we'll walk through it below.
    instance = get_client().get_instance() if not instance

    # Walk through all of our inputs. Each one is a hash thats stored within
    # the inputs array. Each hash has a name/value. For each one, split and
    # parse them appropriately before adding them to our cache.
    cache['inputs'] = {}
    instance.raw['inputs'].each do |k|
      key = clean("rs_input_#{k['name']}")
      value = k['value'].split(':')[1]
      cache['inputs'][key] = value
    end
  end

  if not cache.has_key?('links')
    Facter.debug('rs-facts: fetching links...')
    # Get our instance data object... we'll walk through it below.
    instance = get_client().get_instance() if not instance

    # Walk through all of our links. Each one is a hash thats stored within
    # the inputs array. Each hash has a name/value. For each one, split and
    # parse them appropriately before adding them to our cache.
    cache['links'] = {}
    instance.raw['links'].each do |k|
      key = clean("rs_link_#{k['rel']}")
      value = k['href']
      cache['links'][key] = value
    end
  end

  if not cache.has_key?('tags')
    Facter.debug('rs-facts: fetching tags...')
    # Get our instance data object... we'll walk through it below.
    instance = get_client().get_instance() if not instance

    # Walk through all of our links. Each one is a hash thats stored within
    # the inputs array. Each hash has a name/value. For each one, split and
    r = RightApi::Resources.new(get_client(), '/api/tags', 'tags')
    tags = r.by_resource(:resource_hrefs => [instance.href])

    # Walk through the list of tags returned for the search issued above
    cache['tags'] = {}
    tags[0].raw['tags'].each do |k|
      # Get the tags and store them in the cache
      split_tag = k['name'].split('=')
      key = clean("rs_tag_#{split_tag[0]}")
      value = split_tag[1]
      cache['tags'][key] = value

      # RightScale tags are a bit unique... because the tag name itself can come
      # and go (a user adds, or removes a tag live in the RS interface), we must
      # actually call Factor.add() inside the loop below to make sure that we
      # catch new tags that have been created.
      Facter.add(key) {
        setcode { get_data('tags')[key] }
      }
    end
  end

  # Return the specific data requested (tags, instance, etc).
  return cache[data]
end

# For each instance variable available, iterate through and call Facter.add()
# for each available instance fact. These fact names do not change, so we do
# this outside of the loop of get_data().
get_data('instance').each do |k,v|
  Facter.add(k) {
    setcode { get_data('instance')[k] }
  }
end

# For each instance variable available, iterate through and call Facter.add()
# for each available instance fact. These fact names do not change, so we do
# this outside of the loop of get_data().
get_data('links').each do |k,v|
  Facter.add(k) {
    setcode { get_data('links')[k] }
  }
end

# For each instance variable available, iterate through and call Facter.add()
# for each available instance fact. These fact names do not change, so we do
# this outside of the loop of get_data().
get_data('inputs').each do |k,v|
  Facter.add(k) {
    setcode { get_data('inputs')[k] }
  }
end

cache = get_cache()
if not cache.has_key?('cached')
  Facter.debug("Saving JSON Cache Files")
  File.open("/var/tmp/rs-facts.json","w") {
    |f| f << cache.to_json
  }
end

