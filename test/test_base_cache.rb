# coding: utf-8
require 'se_open_data/utils/base_cache'
require 'minitest/autorun'
require_relative './base_cache_common_specs'

# Tests for SeOpenData::Utils::BaseCache

Minitest::Test::make_my_diffs_pretty!


describe SeOpenData::Utils::BaseCache do
  subject { SeOpenData::Utils::BaseCache.new }
  BaseCacheCommonSpecs::simple_usecases
end
