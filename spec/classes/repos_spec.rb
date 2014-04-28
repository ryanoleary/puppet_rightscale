require 'spec_helper'

describe 'rightscale::repos', :type => 'class' do
  context 'default params' do
    let(:facts) { RSPEC_DEFAULT_FACTS }

    it { should compile.with_all_deps }
    it { should contain_class('Apt::Update') }
    it { should contain_class('Apt::Params') }

    it { should contain_apt__key('9A917D05').with(
      'key_source' => 'http://cf-mirror.rightscale.com/mirrorkeyring/rightscale_key.pub') }

    it { should contain_file('/etc/apt/sources.list.d/rightscale.sources.list').with(
      'ensure'  => 'file',
      'owner'   => 'root',
      'group'   => 'root',
      'mode'    => '0644',
      'replace' => false,
      'content' => /http:\/\/cf-mirror.rightscale.com/,
      'notify'  => 'Class[Apt::Update]') }
    it { should contain_file('/etc/apt/sources.list.d/rightscale_extra.sources.list').with(
      'ensure'  => 'file',
      'owner'   => 'root',
      'group'   => 'root',
      'mode'    => '0644',
      'replace' => false,
      'content' => /http:\/\/cf-mirror.rightscale.com/,
      'notify'  => 'Class[Apt::Update]') }

    it { should_not contain_apt__source('rightscale_security_fallback') }
    it { should_not contain_apt__source('rightscale_security_mirror') }
  end

  context 'with force => true' do
    let(:facts) { RSPEC_DEFAULT_FACTS }
    let(:params) { { 'force' => true } }

    it { should compile.with_all_deps }
    it { should contain_file('/etc/apt/sources.list.d/rightscale.sources.list').with(
      'replace' => true) }
    it { should contain_file('/etc/apt/sources.list.d/rightscale_extra.sources.list').with(
      'replace' => true) }
  end

  context 'fallback_mirror => unittest.com' do
    let(:facts) { RSPEC_DEFAULT_FACTS }
    let(:params) { { 'fallback_mirror' => 'unittest.com' } }

    it { should compile.with_all_deps }
    it { should contain_apt__key('9A917D05').with(
      'key_source' => 'http://unittest.com/mirrorkeyring/rightscale_key.pub') }
    it { should contain_file('/etc/apt/sources.list.d/rightscale.sources.list').with(
      'content' => /http:\/\/unittest.com/) }
    it { should contain_file('/etc/apt/sources.list.d/rightscale_extra.sources.list').with(
      'content' => /http:\/\/unittest.com/) }
  end

  context '$::rs_island => unittest.com' do
    my_facts = RSPEC_DEFAULT_FACTS.clone
    my_facts[:rs_island] = 'unittest.com'
    let(:facts) { my_facts }

    it { should compile.with_all_deps }
    it { should contain_file('/etc/apt/sources.list.d/rightscale.sources.list').with(
      'content' => /http:\/\/unittest.com/) }
    it { should contain_file('/etc/apt/sources.list.d/rightscale_extra.sources.list').with(
      'content' => /http:\/\/unittest.com/) }
  end

  context 'date => 1999/01/01' do
    let(:facts) { RSPEC_DEFAULT_FACTS }
    let(:params) { { 'date' => '1999/01/01' } }

    it { should compile.with_all_deps }
    it { should contain_file('/etc/apt/sources.list.d/rightscale.sources.list').with(
      'content' => /ubuntu_daily\/1999\/01\/01\//) }
    it { should contain_file('/etc/apt/sources.list.d/rightscale_extra.sources.list').with(
      'content' => /rightscale_software_ubuntu\/1999\/01\/01\//) }
  end

  context 'enable_security => latest' do
    let(:facts) { RSPEC_DEFAULT_FACTS }
    let(:params) { { 'enable_security' => 'latest' } }

    it { should compile.with_all_deps }
    it { should contain_apt__source('rightscale_security_fallback').with(
      'location' => 'http://cf-mirror.rightscale.com/ubuntu_daily/latest',
      'release'  => 'precise-security') }
    it { should_not contain_apt__source('rightscale_security_mirror') }
  end

  context 'enable_security => latest, fallback_mirror => unittest.com' do
    let(:facts) { RSPEC_DEFAULT_FACTS }
    let(:params) { { 'enable_security' => 'latest',
                     'fallback_mirror' => 'unittest.com' } }

    it { should compile.with_all_deps }
    it { should contain_apt__source('rightscale_security_fallback').with(
      'location' => 'http://unittest.com/ubuntu_daily/latest') }
    it { should_not contain_apt__source('rightscale_security_mirror') }
  end

  context 'enable_security => latest, $::rs_island => unittest.com' do
    my_facts = RSPEC_DEFAULT_FACTS.clone
    my_facts[:rs_island] = 'unittest.com'
    let(:facts) { my_facts }
    let(:params) { { 'enable_security' => 'latest' } }

    it { should compile.with_all_deps }
    it { should contain_apt__source('rightscale_security_mirror').with(
      'location' => 'http://unittest.com/ubuntu_daily/latest',
      'release'  => 'precise-security') }
  end
end
