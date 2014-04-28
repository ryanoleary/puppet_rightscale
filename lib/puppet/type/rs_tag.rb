# License
#
# Copyright 2014 Nextdoor.com, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Puppet::Type.newtype(:rs_tag) do
  desc "Tags a host in RightScale with the supplied values"

  # Pre-built Regex Patterns for RightScale tag naming.
  #
  # Initial tag 'name' (no predicate)
  rs_tag_name = /^([a-z])([a-z0-9_]+)?/
  # Optional tag 'predicate'
  rs_tag_predicate = /:([a-z])([a-z0-9_]+)?/

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, :namevar => true) do
    desc "Tag name - must conform to RightScale standards"
    validate do |value|
      unless value =~ /#{rs_tag_name}(#{rs_tag_predicate})?$/
        raise ArgumentError, "%s is not a valid tag name" % value
      end
    end
  end

  newproperty(:value) do
    desc "Value of the tag (optional)"
  end

  validate do
    # If the supplied name has a name/predicate, then a value MUST be supplied.
    if self[:name] =~ /#{rs_tag_name}#{rs_tag_predicate}$/ and not self[:value]
      self.fail "You must supply a `value` if your tag `name` includes a predicate."
    end

    # If the value is supplied, then the name MUST have a predicate.
    if not self[:name] =~ /#{rs_tag_name}#{rs_tag_predicate}$/ and self[:value]
      self.fail "You must name your tag with a predicate if you have supplied a `value`."
    end

  end
end
