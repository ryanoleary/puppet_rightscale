# == Class: rightscale::repos
#
# This class forces/allows a puppet-managed host to use the RightScale
# mirrored package repositories.
#
# The default behavior of this class is to protect the repository
# configuration files that RightLink installs on bootup by defining
# file-resources for them, and *not* overwriting their contents.
#
# === Optional Parameters
#
# [*date*]
#   The default frozen repository date to use.
#   (default: latest)
#
# [*enable_security*]
#   Enable's an additional Repo configuration of the 'latest' mirror of the
#   security updates from Ubuntu. Takes either 'latest' or a repo mirror
#   date like '2014/03/13'.
#   (default: false)
#
# [*fallback_mirror*]
#   The name of the fallback mirror location. This is still a RightScale
#   specific mirror and must conform to the RightScale mirror file structure.
#   (default: cf-mirror.rightscale.com)
#
# [*force*]
#   Whether or not to overwrite existing repository configuration files.
#   If the file exists already, setting this to false will let Puppet skip
#   overwriting the contents of the file -- useful if you want to use
#   the 'frozen repository' feature from RightScale. If you set this to
#   true, you will always overwrite the contents of the config files.
#   (default: false)
#
# === Requirements
#
# This module depends on the puppetlabs apt module to be available.
# (https://forge.puppetlabs.com/puppetlabs/apt)
#
# === Examples
#
#   class { 'rightscale::repos':
#     force => false,
#     date  => '2014/03/13';
#   }
#
# === Authors
#
# Matt Wise <matt@nextdoor.com>
#
class rightscale::repos (
  $date            = 'latest',
  $enable_security = false,
  $force           = false,
  $fallback_mirror = 'cf-mirror.rightscale.com',
) {
  # Include the puppetlabs apt module so we can notify it of updates.
  include apt::update

  # Include the apt::params package so we can find out where we should put
  # our source lists if they're missing.
  include apt::params
  $sources_list_d = $apt::params::sources_list_d

  # If $force is true, then we adjust the behavior of a few file resources.
  case $force {
    true: {
      $apt_file_replace = true
    }
    default: {
      $apt_file_replace = false
    }
  }

  # If the server has the rs_island fact defined, we use that as our mirror
  # location primarily in the event that we're creating the repo configuration
  # files from scratch. If not, we use the fallback_mirror above.
  case $::rs_island {
    undef: {
      $mirror = undef
    }
    default: {
      $mirror = $::rs_island
    }
  }

  # Install the RightScale GPG Signing Key
  apt::key { '9A917D05':
    key_source => "http://${fallback_mirror}/mirrorkeyring/rightscale_key.pub",
  }

  # Set up the Ubuntu mirror apt configuration files. Rather than leveraging
  # the apt::source resource, we push specifically configured files. This
  # allows us to leverage the File resources's 'replace' option to not replace
  # existing RightLink-supplied source files. If they are missing, then puppet
  # will push our default versions as configured by this module.
  #
  # If $force is set to True, then we override them no matter what.
  #
  file {
    "${sources_list_d}/rightscale.sources.list":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    replace => $apt_file_replace,
    content => template('rightscale/rightscale.sources.list.erb'),
    notify  => Class['apt::update'];

    "${sources_list_d}/rightscale_extra.sources.list":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    replace => $apt_file_replace,
    content => template('rightscale/rightscale_extra.sources.list.erb'),
    notify  => Class['apt::update'];
  }

  # If the enable_security flag is flipped, then manage an additional
  # RightScale repository that has the absolute latest security updates from
  # Ubuntu.
  if $enable_security {
    # If the $mirror variable is discovered above, then set up the local
    # mirror. If not, skip it and rely on the fallback mirror.
    if $mirror {
      apt::source { 'rightscale_security_mirror':
        location    => "http://${mirror}/ubuntu_daily/${enable_security}",
        include_src => false,
        release     => "${::lsbdistcodename}-security",
        repos       => 'main restricted universe multiverse';
      }
    }
    $loc = "http://${fallback_mirror}/ubuntu_daily/${enable_security}"
    apt::source { 'rightscale_security_fallback':
      location    => $loc,
      include_src => false,
      release     => "${::lsbdistcodename}-security",
      repos       => 'main restricted universe multiverse';
    }
  }
}
