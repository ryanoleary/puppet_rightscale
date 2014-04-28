require 'spec_helper'
require "#{File.join(File.dirname(__FILE__),'..','..','..','lib','puppet','type','rs_tag')}"


describe Puppet::Type.type(:rs_tag) do
  let :tag do
    Puppet::Type.type(:rs_tag).new(
      :name  => 'test')
  end

  it 'name => test' do
    tag[:name] = 'test'
    tag[:name].should == 'test'
  end

  it 'name => $!@ should fail' do
    lambda { tag[:name] = '$!@' }.should raise_error(Puppet::Error)
  end

  it 'name => BadTagName should fail' do
    lambda { tag[:name] = 'BadTagName' }.should raise_error(Puppet::Error)
  end

  it 'name => missing_predicate: should fail' do
    lambda { tag[:name] = 'missing_predicate:' }.should raise_error(Puppet::Error)
  end

  it 'name => name:predicate, value => nil should fail' do
    lambda {
      Puppet::Type.type(:rs_tag).new(
      :name  => 'name:predicate')
    }.should raise_error(Puppet::Error)
  end

  it 'name => name_without_predicate, value => foobar should fail' do
    lambda {
      Puppet::Type.type(:rs_tag).new(
      :name  => 'name_without_predicate',
      :value => 'foobar')
    }.should raise_error(Puppet::Error)
  end

  it 'name => name:predicate, value => something' do
    Puppet::Type.type(:rs_tag).new(
      :name  => 'name:predicate',
      :value => 'something')
  end

  it 'value => test' do
    tag[:value] = 'test'
    tag[:value].should == 'test'
  end
end
