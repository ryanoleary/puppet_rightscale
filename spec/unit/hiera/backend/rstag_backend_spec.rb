require 'spec_helper'
require 'logging'
require File.join(File.dirname(__FILE__), '../../../../lib/hiera/backend/rstag_backend.rb')

# Enable rspec-mock
RSpec.configure do |config|
  config.mock_framework = :rspec
end

Logging.logger.root.appenders = Logging.appenders.stdout
Logging.logger.root.level = :warn

class Hiera
  module Backend
    describe Rstag_backend do
      before :each do
        # Stub the logging, since it doesn't normally work in the spec tests.
        Hiera.stub :debug
        Hiera.stub :warn

        # Mock the RightScale backend
        @client = double("RightScale")
        allow(@client).to receive(:new) { @client }
        allow(@client).to receive(:get_config) { configs }
        stub_const("RightScale", @client)
        @backend = Rstag_backend.new()

        # Mock the :prefix method to return a special prefix for
        # unit testing purposes. Turns out that mocking Hiera can be tricky
        # because of all of the global variables involved, so moving the
        # prefix setting into its own method makes it easier for us mock
        # out just that method.
        @backend.stub(:prefix) { 'unittest_' }
      end

      describe '#initialize' do
        it 'should print debug through Hiera' do
          Hiera.should_receive(:debug).with('[RSTag] Hiera Backend Initialized')
          Rstag_backend.new()
        end
      end

      describe '#debug' do
        it 'should append the [RSTag] prefix' do
          Hiera.should_receive(:debug).with('[RSTag] Unittest')
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
    end
  end
end
