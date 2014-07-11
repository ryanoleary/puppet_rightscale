# == Class: rightscale
#
# Sets up default settings for a RightScale managed host
#
# === Optional Parameters
#
# [*right_api_client*]
#   rightscale_api_client Gem version to install
#
# [*right_aws*]
#   right_aws Gem version to install
#
# [*rest_client*]
#   Supporting rest_client Gem Version to Install
#
# === Authors
#
# Matt Wise <matt@nextdoor.com>
#
class rightscale (
  $right_api_client = $rightscale::params::right_api_client,
  $right_aws        = $rightscale::params::right_aws,
  $rest_client      = $rightscale::params::rest_client,
) inherits rightscale::params {
  # Install the required gems in order. These gems support the custom Hiera
  # backend as well as the puppet rs-facts plugin that gathers common
  # RightScale facts.
  package {
    'rest-client':
    ensure   => $rest_client,
    provider => 'gem';

    'right_aws':
    ensure   => $right_aws,
    provider => 'gem',
    require  => Package['rest-client'];

    'right_api_client':
    ensure   => $right_api_client,
    provider => 'gem',
    require  => Package['rest-client'];
  }
}
