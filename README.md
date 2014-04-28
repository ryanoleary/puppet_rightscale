# Puppet and RightScale Integration Libraries

This module provides a standard and secure way of bootstrapping hosts in
RightScale while using Puppet as your configuration management tool. The
module includes the following components:

 * Puppet Plugin: RightScale Facter Plugin
 * Puppet Plugin: RightScale Tagger Plugin
 * Puppet Plugin: Autosign Approver
 * Hiera RightScale Backend

## RightScale Facter Plugin

The [rs-facts.rb](lib/facter/rs-facts.rb) gathers facts from RightScale
managed hosts through both local files and the live RightScale 1.5 API.
In the event that your host is not a RightScale-managed host, the plugin
fails quickly and silently.

### Installation Requirements

 * Ruby Gem: [right\_api\_client](https://github.com/rightscale/right_api_client)

   Puppet automatically copies over all plugins from the master to clients
   at the beginning of each run. The first time this plugin is loaded, it
   checks for the presence of the gem. If the gem is not installed, it never
   tries again to load it. Due to this behavior of Facter, you must have the
   `right_api_client` gem installed during your pre-puppet boot scripts.

   *Note*: This is done by the RightScale Cookbook, if you use it.

### Facts Gathered

This plugin pulls facts from two sources. The local
`/var/spool/cloud/user-data.dict` file installed by the RightLink agent, and
the native RightScale API. In both cases, the facts returned are dynamically
generated. This is a brief list of the facts you can resasonably expect to
see ... but these facts may change if RightScale changes the data that they
expose at any point in the future.

#### /var/spool/cloud/user-data.dict facts:

These facts are loaded one time and are expected to not change during the
runtime of the Puppet daemon. They are likely set at the instantiation time
of the instance itself, and never change.

*Note*: The `rs_api_token` fact is used as the credentials for the next
phase of the plugin (accessing the API).

 * `rs_account`: RightScale Account Number
 * `rs_api_token`: RightScale Account Number and matching Instance API Token
 * `rs_api_url`: Host Instance API URL
 * `rs_rn_auth`: RightScale Instance API Token
 * `rs_rn_host`: Remote RightScale Communication Broker Host
 * `rs_rn_id`: RightScale Internal Instance ID
 * `rs_rn_url`: Remote RightScale Communication Broker Host URL
 * `rs_server`: RightScale Remote Cloud URL
 * `rs_sketchy`: RightScale Monitoring (*collectd*) Endpoint

#### RightScale API-Gathered Facts

The `right_api_client` gem is used to reach out to the RightScale API and
gather as many facts about the host as possible. The plugin gathers local
instance data, server launch inputs, server HREF links, and finally it pulls
the current tags associated with a host.

*TODO*: Gather facts from the deployment a host is in as well.

*Note*: The design around Facter plugins is that you provide the plugin a set list
of *facts* and then for each fact, you provide a *method* for getting that
facts updated data. With most facts (like *memfree*), getting this data
on each Puppet run is simple and fast. With remote-accessed Facts though,
this can be tricky. Especially when these facts have the ability to change
during a servers lifetime (for example, updated RightScale tags).

To combat this, this plugin keeps a cache of all of the fact data with an
extremely short TTL. Each fact defined (by the *Facter.add* method) is given
a *get fact from cache* method that can be called as often as necessary. This
method checks the age of the cache, and either returns the cached data or
calls out to the RightScale API for updated data.

##### Instance Facts:

 * `rs_created_at`
 * `rs_link_alerts`
 * `rs_link_cloud`
 * `rs_link_datacenter`
 * `rs_link_deployment`
 * `rs_link_image`
 * `rs_link_inputs`
 * `rs_link_instance_type`
 * `rs_link_kernel_image`
 * `rs_link_monitoring_metrics`
 * `rs_link_multi_cloud_image`
 * `rs_link_parent`
 * `rs_link_server_template`
 * `rs_link_ssh_key`
 * `rs_link_volume_attachments`
 * `rs_monitoring_id`
 * `rs_monitoring_server`
 * `rs_name`
 * `rs_pricing_type`
 * `rs_private_dns_names_0`
 * `rs_private_ip_addresses_0`
 * `rs_public_dns_names_0`
 * `rs_public_ip_addresses_0`
 * `rs_resource_uid`
 * `rs_state`
 * `rs_updated_at`
 * `rs_user_data`

##### Server Tags:

Every tag directly associated with a host is added with the `rs_tag_` prefix.
Tag names undergo a bit of a transformation to be more *Puppet-friendly*
(colons replaced with underscores, all text lowercased, etc). Here are some
example tag names:

 * `rs_tag_rs_login_state`
 * `rs_tag_rs_monitoring_state`

##### Instance Inputs:

Every *server input* provided to the boot scripts is provided here similarly
to how the Tag names are. Slashes, colons and other funny characters are
stripped or munged. Example facts look like this:

 * `rs_input_sys_swap_file`
 * `rs_input_sys_swap_size`

## RightScale Tagger Plugin

This plugin allows the Puppet client agent on a server to tag itself in
RightScale using the `rs_tag` command. Usage is very simple, and enforces
the RightScale requirements described here:

  http://support.rightscale.com/12-Guides/RightScale_101/06-Advanced_Concepts/Tagging

### Example Usage

Creating some tags:

    rs_tag { 'MyTag': ensure => 'present' }
    rs_tag { 'MyTag::State': value => 'XYZ' }

Destroying tags:

    rs_tag { 'MyTag': ensure => 'absent' }

## RightScale Autosign Plugin

This script provides policy based certificate auto-signing for Puppet with
RightScale integration.  It's intended for use as a custom policy
executable, which your Puppet master will call upon every certificate
signing request. When this script exists with 0 status, then we tell Puppet
to sign the certificate.  When the script exits with a non-zero status, such
as 1, we tell Puppet not to sign the certificate.

Puppet clients must be populated with special data prior to the CSR
generation and Chef can be used to bootstrap.  See this repo for examples:

https://github.com/Nextdoor/public_cookbooks/tree/master/nd-puppet

Also see the Puppet documentation for more information on configuring your
Puppet master and clients:

 * [Autosigning Certificate Requests - Custom Policy Executables](http://bit.ly/1fGkhPW)
 * [CSR Attributes and Certificate Extensions](http://bit.ly/1gTaXw9)

### Puppet Master Configuration

#### Enabling the external autosigner

On your Puppet Master Certificate Authority server (CA), you will want to
modify your `/etc/puppet/puppet.conf` file to point to the `autosign.rb`
file in this Puppet module. Our configuration looks like this:

    # This script is executed by the Puppet Master any time a certificate
    # signing is required. If the script exits with a 0, the cert will be
    # signed.
    #
    # NOTE: $environment here refers to the environment that the puppet
    # master is configured to use. See the 'environment' setting a few lines
    # up.
    autosign = /mnt/puppet/$environment/modules/rightscale/lib/etc/autosign.rb

#### Configuring the autosigner

The script also depends on your Puppet master having configured credentials
for accessing the RightScale API. Because these credentials can be used to
browse your entire RightScale account, you must keep them private. We strongly
recommend having a manual or semi-manual process that installs the config
file to `/etc/puppet/rightscale.conf`, rather than checking this file into your
actual code repository.

You must specify a challange password and one or more account sections with
RightScale credentials.

You must also specify a custom RightScale `tag` in the global section which we
use to search for and validate the instace with RightScale.  Please note,
RightScale tags follow the format `namespace:predicate=value`.  We
recommend you assign this tag to new instances and set it to a unique and
random value on each server bootup.

You can optionally enable logging with the debug option, which accepts a
filename as a parameter.

Here's an example configuration file that has two RightScale account
identifiers, 1234 and 5678:

    [global]
    challange_password = '...'
    tag = 'namespace:predicate'
    debug = /path/to/debug.log
     
    [1234]
    email = '...'
    password = '...'
    api_url = 'https://my.rightscale.com'
    
    [5678]
    oath2_token = '...'
    api_url = 'https://us-3.rightscale.com'

##### RightScale Credential Notes

You are able to use *either* a `email`/`password` combination, or the
`oath2_token` to access RightScale. If you supply an `oath2_token` it will
be used by default, overriding the `email`/`password` settings.

We strongly encourage you to create a special `observer` account in
RightScale, and generate an Oauth2 token for that account. In many cases
you can grant this single user account permission to multiple RightScale
accounts, which means you only have to manage and secure one credential set.

Also, if you know your API endpoint, we suggest inserting it in above. If you
do not, the client will first access `my.rightscale.com`, and then be
redirected to the appropriate endpoint -- this adds about *2 seconds* of
latency to your API calls.

## Hiera RightScale Backend

The Hiera `rstag` backend allows your Puppet Master to search RightScale for
tags matching a given expression, and return all of the unique values
associated with those tags. This allows you to tag machines as providing
a particular service, and then use that tag to discover the servers
dynamically in your puppet manifests.

Here's an example:

    $syslog_servers = hiera('svc_syslog:production')

Since you have the power of Hiera at your fingertips, you can choose your
hierarchy to put priority on the `rstag` backend, or have your priority
focus on local YAML files and fall-back to the `rstag` plugin. Additionally,
you can always have a failsafe:

    $syslog_servers = hiera('svc_syslog:production', 'syslog.mydomain.com')

### Hiera Configuration

In order to prevent all `hiera()` lookups from going to the RightScale
API (*which is very slow*), you must configure your `rstag` hiera backend
to only pay attention to particular Hiera keynames. For example, take this
Hiera config:

    ---
    :backends:
      - yaml
      - rstag
    :yaml:
      :datadir: %{settings::manifestdir}/hiera
      :rightscale:
        :tag_prefix: "my_svc_"
      :hierarchy:
        - hosts/%{hostname}
        - %{domain}
        - default

The above configuration guarantees that only lookups that start with the word
`my_svc_` will trigger the remote lookup via RightScale. For example:

    $syslog_srevers = hiera('my_svc_syslog:prod')

### Server Configuration

This plugin requires the same `rightscale.conf` plugin configuration file
described above in order to function properly.

### Why a Hiera backend?

There are several advantages to leveraging the
[Hiera](http://docs.puppetlabs.com/hiera/1/custom_backends.html) backend
module rather than building a
[custom function](http://docs.puppetlabs.com/guides/custom_functions.html).
Overall the Hiera backend module is more suited to providing structured
data back to your Puppet manifests. It offers several avantages to a standard
puppet function:

  * Individual `hiera()` calls can specify their fallback default value, rather
    than trying to program that behavior into the plugin.

  * Spec tests can easily mock the results of the `hiera()` lookkup to simulate
    different return values and their behaviors.

  * Mixing-and-matching of local hiera data backends (YAML, JSON, etc) with
    the RightScale backend.
