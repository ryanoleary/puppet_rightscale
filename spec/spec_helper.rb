require 'rubygems'
require 'simplecov'
require 'simplecov-csv'
require 'puppetlabs_spec_helper/module_spec_helper'

# Configure the coverage reporter
SimpleCov.start do
  add_filter '/spec/'
end
SimpleCov.refuse_coverage_drop
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CSVFormatter,
]
SimpleCov.at_exit do
  SimpleCov.result.format!
end
