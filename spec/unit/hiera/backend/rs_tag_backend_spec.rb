require 'spec_helper'
require 'logging'
require File.join(File.dirname(__FILE__), '../../../../lib/hiera/backend/rs_tag_backend.rb')

# Enable rspec-mock
RSpec.configure do |config|
  config.mock_framework = :rspec
end

Logging.logger.root.appenders = nil
#Logging.logger.root.appenders = Logging.appenders.stdout
#Logging.logger.root.level = :error

class Hiera
  module Backend
    describe Rs_tag_backend do
      before :each do
        # Stub the logging, since it doesn't normally work in the spec tests.
        Hiera.stub :debug
        Hiera.stub :warn

        # Mock the RightScale backend
        @client = double("RightScale")
        allow(@client).to receive(:new) { @client }
        allow(@client).to receive(:get_config) { configs }
        stub_const("RightScale", @client)
        @backend = Rs_tag_backend.new()

        # Mock the :prefix method to return a special prefix for
        # unit testing purposes. Turns out that mocking Hiera can be tricky
        # because of all of the global variables involved, so moving the
        # prefix setting into its own method makes it easier for us mock
        # out just that method.
        @backend.stub(:prefix) { 'unittest_' }

        # Mock the cache timeout to 5 seconds
        @backend.stub(:cache_timeout) { 5 }
      end

      describe '#initialize' do
        it 'should print debug through Hiera' do
          Hiera.should_receive(:debug).with('[rs_tag_backend] Hiera Backend Initialized')
          Rs_tag_backend.new()
        end
      end

      describe '#debug' do
        it 'should append the [rs_tag_backend] prefix' do
          Hiera.should_receive(:debug).with('[rs_tag_backend] Unittest')
          @backend.debug('Unittest')
        end
      end

      describe "#lookup" do
        it 'should return nil for missing path/value quickly' do
          @backend.lookup(nil, :scope, :override, :priority).should be nil
        end

        it 'should return nil for key missing key prefix' do
          @backend.lookup('bad_key', :scope, :override, :priority).should be nil
        end

        it 'should return one server' do
          tag_name    = 'unittest_myservice'
          tag_results = [ 'unittest_myservice=value1' ]
          expected    = [ 'value1' ]
          @client.should_receive(:get_tags_by_tag).once.with(tag_name).and_return(tag_results)
          @backend.lookup('unittest_myservice', :scope, :override, :priority).should == expected
        end

        it 'should return multiple servers' do
          tag_name    = 'unittest_myservice'
          tag_results = [ 'unittest_myservice=value1', 'unittest_myservice=value2' ]
          expected    = [ 'value1', 'value2' ]
          @client.should_receive(:get_tags_by_tag).once.with(tag_name).and_return(tag_results)
          @backend.lookup('unittest_myservice', :scope, :override, :priority).should == expected
        end

        it 'should return no servers' do
          tag_name    = 'unittest_myservice'
          tag_results = [ ]
          expected    = [ ]
          @client.should_receive(:get_tags_by_tag).once.with(tag_name).and_return(tag_results)
          @backend.lookup('unittest_myservice', :scope, :override, :priority).should == expected
        end
      end

      describe "#search" do
        it "should call get_tags_by_tag once for one search" do
          tag_name    = 'unittest_myservice'
          tag_results = [ 'unittest_myservice=value1' ]
          expected    = [ 'value1' ]
          @client.should_receive(:get_tags_by_tag).once.with(tag_name).and_return(tag_results)
          @backend.search('unittest_myservice').should == expected
          @backend.instance_variable_get('@cache').has_key?('unittest_myservice').should == true
        end

        it "should call get_tags_by_tag once and then cache results" do
          tag_name    = 'unittest_myservice'
          tag_results = [ 'unittest_myservice=value1' ]
          expected    = [ 'value1' ]
          @client.should_receive(:get_tags_by_tag).once.with(tag_name).and_return(tag_results)
          @backend.search('unittest_myservice').should == expected
          @backend.instance_variable_get('@cache').has_key?('unittest_myservice').should == true
          @backend.search('unittest_myservice').should == expected
          @backend.search('unittest_myservice').should == expected
        end

        it "should not store an item in the cache if the cache_timeout is nil" do
          tag_name    = 'unittest_myservice'
          tag_results = [ 'unittest_myservice=value1' ]
          expected    = [ 'value1' ]
          @backend.stub(:cache_timeout) { nil }
          @client.should_receive(:get_tags_by_tag).once.with(tag_name).and_return(tag_results)
          @backend.search('unittest_myservice').should == expected
          @backend.instance_variable_get('@cache').has_key?('unittest_myservice').should == false
        end
      end

      describe "#get_from_cache" do
        it "should fail if item not in cache" do
          @backend.get_from_cache('foobar').should == false
        end

        it "should fail if item in cache, but missing timestamp" do
          mocked_cache = { 'foobar' => { :values => 'abcd' } }
          @backend.instance_variable_set("@cache", mocked_cache)
          @backend.get_from_cache('foobar').should == false
        end

        it "should fail if the timestamp is expired" do
          mocked_cache = {
                  'foobar' => {
                    :timestamp => Time.now.to_i - 10,
                    :values => 'abcd' } }
          @backend.instance_variable_set("@cache", mocked_cache)
          @backend.get_from_cache('foobar').should == false
          @backend.instance_variable_get("@cache")['foobar'].should == nil
        end

        it "should succeed if the key exists and timestamp is fresh" do
          mocked_cache = {
                  'foobar' => {
                    :timestamp => Time.now.to_i,
                    :values => 'abcd' } }
          @backend.instance_variable_set("@cache", mocked_cache)
          @backend.get_from_cache('foobar').should == 'abcd'
        end
      end
    end
  end
end
