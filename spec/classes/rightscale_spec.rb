require 'spec_helper'

# Facts mocked up for unit testing
FACTS = {
  :osfamily => 'Debian',
  :operatingsystem => 'Ubuntu',
  :operatingsystemrelease => '12',
  :lsbdistid => 'Ubuntu',
  :lsbdistcodename => 'precise',
  :lsbdistrelease => '12.04',
  :lsbmajdistrelease => '12',
  :kernel => 'linux',
}

describe 'rightscale', :type => 'class' do
  context 'default params' do
    let(:facts) { FACTS }
    it do
      should compile.with_all_deps
      should contain_package('rest_client').with(
        'ensure' => '1.6.7')
      should contain_package('right_aws').with(
        'ensure' => '3.1.0')
      should contain_package('right_api_client').with(
        'ensure' => '1.5.19')
    end
  end
end
