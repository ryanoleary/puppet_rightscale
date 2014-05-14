require 'spec_helper'
require 'logging'
require 'right_api_client'
require 'uri'
require File.join(File.dirname(__FILE__), '../../lib/rightscale.rb')

# Enable rspec-mock
RSpec.configure do |config|
  config.mock_framework = :rspec
end

class FakeClient
  def post(url, post_data, args, &callback)
    response = '{"access_token": "abcdef" }'
    callback.call(response, nil, nil)
  end
end

Logging.logger.root.appenders = nil
#Logging.logger.root.appenders = Logging.appenders.stdout
#Logging.logger.root.level = :warn

describe RightScale do
  before :each do
    # Mock the RightApi::Client to respond with a mocked object
    @mocked_api_client = double("RightApi::Client")
    stub_const("RightApi::Client",  @mocked_api_client)

    # Mock the RestClient::Resource to always respond with a mocked object
    @mocked_rest_client = double("RestClient")
    response = double
    response.stub(:code) { 200 }
    response.stub(:body) { '{"access_token": "abcdef" }' }
    response.stub(:headers) { {} }
    @mocked_rest_client.stub(:post) {response }
    stub_const("RestClient", @mocked_rest_client)

    # Mock the config list to pass in a specific config file
    stub_const("RightScale::POTENTIAL_CONFIGS",
      [File.join(File.dirname(__FILE__), '..', 'fixtures', 'valid_config')])

    # Lastly, create our RightScale class object
    @rs = RightScale.new()
  end

  it "#new" do
    @rs.should be_an_instance_of RightScale
  end

  ######################
  # get_config() tests #
  ######################
  it "get_config() should be idempotent" do
    first_config = @rs.get_config()
    second_config = @rs.get_config()
    first_config.should be second_config
  end

  it "get_config() should fail if no configs found" do
    stub_const("RightScale::POTENTIAL_CONFIGS", [])
    expect { @rs.get_config() }.to raise_error(/Could not find/)
  end

  it "get_config() with empty config file should fail" do
    stub_const("RightScale::POTENTIAL_CONFIGS",
      [File.join(File.dirname(__FILE__), '..', 'fixtures', 'empty_config')])
    expect { @rs.get_config() }.to raise_error(/global section/)
  end

  it "get_config() with config file missing stanzas should fail" do
    stub_const("RightScale::POTENTIAL_CONFIGS",
      [File.join(File.dirname(__FILE__), '..', 'fixtures', 'missing_stanzas')])
    expect { @rs.get_config() }.to raise_error(/at least one account/)
  end

  it "get_config() with config file missing global stanzas should fail" do
    stub_const("RightScale::POTENTIAL_CONFIGS",
      [File.join(File.dirname(__FILE__), '..', 'fixtures', 'missing_global')])
    expect { @rs.get_config() }.to raise_error(/global section/)
  end

  it "get_config() with valid config file should return config" do
    stub_const("RightScale::POTENTIAL_CONFIGS",
      [File.join(File.dirname(__FILE__), '..', 'fixtures', 'valid_config')])
    @rs.get_config()['account1']['email'].should == 'email'
    @rs.get_config()['account2']['oath2_token'].should == '1234'
  end

  #########################
  # get_client() tests #
  #########################
  it "get_clients() should return two instances" do
    # Mock the RightApi::Client.new() method so we don't really make
    # outbound web calls during unit tests.
    @mocked_api_client.should_receive(:new).twice
    @mocked_rest_client.should_receive(:post).once
    @rs.get_clients()
  end

  it "get_clients() should return the same clients each time" do
    # Mock the RightApi::Client.new() method so we don't really make
    # outbound web calls during unit tests.
    @mocked_api_client.should_receive(:new).twice
    @mocked_rest_client.should_receive(:post).once
    first_clients = @rs.get_clients()
    second_clients = @rs.get_clients()
    first_clients.should be second_clients
  end

  ############################
  # get_access_token() tests #
  ############################
  it "get_access_token() should return a token" do
    # Re-stub the client to return a proper API key back for this test
    response = double
    response.stub(:code) { 200 }
    response.stub(:body) { '{"access_token": "abcdef" }' }
    response.stub(:headers) { {} }
    @mocked_rest_client.stub(:post).with({
       :url => "https://my.rightscale.com/api/oauth2",
       :payload => {
         "refresh_token" => { :refresh_token => "abc" },
         "grant_type"    => "refresh_token"},
       :timeout => 15,
       :content_type=>"application/x-www-form-urlencoded",
        :X_API_VERSION=>"1.5", :accept=>"*/*"}
      ) { response }

    # Make the call and pass in any fake token we want
    token = @rs.get_access_token(:refresh_token => 'abc')

    # Should get back abcdef as our actual api token
    token.should == 'abcdef'
  end

  it "get_access_token() should raise exception if error code" do
    # Re-stub the client to return a proper API key back for this test
    response = double
    response.stub(:code) { 401 }
    @mocked_rest_client.stub(:post) { response }

    # Make the call and pass in any fake token we want
    expect { @rs.get_access_token(:refresh_token => 'abc') }.to raise_error(/FAILED/)
  end

  ######################
  # get_client() tests #
  ######################
  it "get_client() with oath2_token should get an access token" do
    # Mock the get_access_token() method so we can track it
    @rs.stub(:get_access_token).and_return('12d3')

    # The RightApi::Client should get called
    @mocked_api_client.stub(:new).once()
    @rs.get_client('123', 'email', 'password', 'oath2_token', 'http://unittest')
  end

  it "get_client() without oath2_token should get an access token" do
    # The RightApi::Client should get called
    @mocked_api_client.stub(:new).once()
    @rs.get_client('123', 'email', 'password', nil, 'http://unittest')
  end

  it "get_client() with missing parameters should fail" do
    expect { @rs.get_client('123', nil, nil, nil, nil) }.to raise_error(/missing/)
  end

  ###########################
  # get_tags_by_tag() tests #
  ###########################
  it "get_tags_by_tag() should work" do
    # Create two fake resource_tag doubles that look like
    # a RightApi resource_tag
    fake_resource_1 = double
    fake_resource_1.stub(:tags) { [ { "name" => "fake_tag1" } ] }
    fake_resource_2 = double
    fake_resource_2.stub(:tags) { [ { "name" => "fake_tag2" } ] }

    # The two resources are listed multiple times here, and out of
    # order, to test that the final dataset is sorted and unqued.
    fake_nested_data_set = [
      fake_resource_2, fake_resource_1, fake_resource_1, fake_resource_2 ]

    # Mock out the get_clients() method and return a fake client
    fake_client = [ double ]
    @rs.stub(:get_clients).and_return(fake_client)
    # Create a second mock that will be used to fake out <client>.tags
    fake_client_tags = double
    # Return a static nested data set
    fake_client_tags.stub(:by_tag) { fake_nested_data_set }
    fake_client[0].stub(:account_id) { '123' }
    fake_client[0].stub(:tags) { fake_client_tags }

    # Now execute the search
    t = @rs.get_tags_by_tag('unittest')
    t.should == [ 'fake_tag1' , 'fake_tag2' ]

    # Now execute the search, but turn deduping off
    t = @rs.get_tags_by_tag('unittest', false)
    t.should == ['fake_tag1', 'fake_tag1', 'fake_tag2', 'fake_tag2']
  end

  ###################################
  # split_tag_for_searching() tests #
  ###################################
  it "split_tag_for_searching() should work" do
    @rs.split_tag_for_searching('nd').should == ['nd', nil, nil]
    @rs.split_tag_for_searching('nd:auth').should == ['nd', 'auth', nil]
    @rs.split_tag_for_searching('nd:auth=foo').should == ['nd', 'auth', 'foo']
    @rs.split_tag_for_searching('nd:auth=foo=bar').should == ['nd', 'auth', 'foo=bar']
  end
end
