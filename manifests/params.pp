# == Class: rightscale::params
#
# Variables and versions for the RightScale class
#
# === Authors
#
# Matt Wise <matt@nextdoor.com>
#
class rightscale::params {
  # TODO: When supporting other OS's, will update this class with a big case
  # statement. For now, this supports Ubuntu 10/12 with Ruby 1.8.
  $right_api_client = '1.5.19'
  $right_aws        = '3.1.0'
  $rest_client      = '1.6.7'
}
