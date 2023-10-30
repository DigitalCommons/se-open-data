# coding: utf-8
require 'se_open_data/utils/hash_cache'
require 'minitest/autorun'
require_relative './base_cache_common_specs'

# Tests for SeOpenData::Utils::HashCache

Minitest::Test::make_my_diffs_pretty!

temp_dir = __dir__+"/temp"

# Clear temp_dir
FileUtils.rm_rf(temp_dir)
FileUtils.mkdir_p(temp_dir)


path = File.join(temp_dir, 'hashcache.json')

describe SeOpenData::Utils::HashCache do
  subject { SeOpenData::Utils::HashCache.new }
  let(:cache2) { SeOpenData::Utils::HashCache.new }
  BaseCacheCommonSpecs::simple_usecases
  BaseCacheCommonSpecs::save_load_usecases(path)
end


