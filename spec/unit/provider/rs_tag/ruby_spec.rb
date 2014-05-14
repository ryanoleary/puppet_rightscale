require 'spec_helper'
require "#{File.join(File.dirname(__FILE__),'..','..','..','..','lib','puppet','type','rs_tag')}"
require "#{File.join(File.dirname(__FILE__),'..','..','..','..','lib','puppet','provider','rs_tag','ruby')}"

provider_class = Puppet::Type.type(:rs_tag).provider(:ruby)

describe provider_class do
  let(:resource) { Puppet::Type.type(:rs_tag).new(
    { :name     => 'test',
      :provider => described_class.name }
  )}
  let(:provider) { resource.provider }

  before :each do
    # Mocked list of existing tags to run our tests against
    existing_tags = '[ "test_tag_1", "test_tag:with_predicate=1" ] '
    Puppet::Util.stubs(:which).with('rs_tag').returns('/usr/bin/rs_tag')
    provider.class.stubs(:rs_tag).with(['--list', '--format', 'json']).returns(existing_tags)
  end

  let(:instance) { provider.class.instances.first }

  describe 'self.prefetch' do
    it 'exists' do
      provider.class.instances
      provider.class.prefetch({})
    end

    it 'should work with rs_tag failure' do
      provider.class.stubs(:rs_tag).with(['--list', '--format', 'json']).raises(Puppet::ExecutionFailure, "Error")
      provider.class.instances.should == nil
      provider.class.prefetch({}).should == nil
    end
  end

  describe 'exists?' do
    it 'checks if `test` tag exists (should not)' do
       provider.exists?.should be_false
    end
  end

  describe 'self.instances' do
    it 'returns an array of tags' do
      instances = provider.class.instances.collect {|x| x.name }
      [ 'test_tag_1', 'test_tag:with_predicate' ].should match_array(instances)
    end
  end

  describe 'self.get_tags' do
    it 'should return a list of providers' do
      providers = provider.class.get_tags()
      providers.length.should == 2
    end
  end

  describe 'self.get_tags with tag: name:predicate=test=foo=bar' do
    it 'should return a correct tag list' do
      existing_tags = '[ "name:predicate=test=foo=bar" ] '
      provider.class.stubs(:rs_tag).with(['--list', '--format', 'json']).returns(existing_tags)

      providers = provider.class.get_tags()
      providers.length.should == 1
      providers[0].name.should == 'name:predicate'
      providers[0].value.should == 'test=foo=bar'
    end
  end

  describe 'self.get_tags() with no tags set' do
    it 'should return an empty array' do
      existing_tags = '[]'
      provider.class.stubs(:rs_tag).with(['--list', '--format', 'json']).returns(existing_tags)
      providers = provider.class.get_tags()
      providers.length.should == 0
    end
  end

  describe 'self.get_tags() with failed rs_tag output' do
    it 'should return nil' do
      existing_tags = 'bogus output'
      provider.class.stubs(:rs_tag).with(['--list', '--format', 'json']).returns(existing_tags)
      providers = provider.class.get_tags()
      providers.should == nil
    end
  end

  describe 'create' do
    it 'should allow creation of the tag `test`' do
      provider.class.expects(:rs_tag).with(['--add', 'test'])
      provider.create
    end
  end

  describe 'destroy' do
    it 'should allow removal of the tag `test`' do
      provider.class.expects(:rs_tag).with(['--remove', 'test'])
      provider.destroy
    end
  end
end
