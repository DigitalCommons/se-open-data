require 'se_open_data/utils/base_cache'
require 'json'

# This is an implementation of SeOpenData::Utils::BaseCache which
# is backed by a JSON file.
#
# The JSON data file should contain a single object containing purely
# string values.  This class is agnostic about this, but nested JSON
# is not supported by the `geocoder` library. The formatting of the
# JSON does not matter, but when saved it will be indented "prettily",
# which adds inspectability at the expense of a little more space.
#
# It adds an `at_exit` hook to save the cache data even if it is not
# done explicitly.
class SeOpenData::Utils::HashCache < SeOpenData::Utils::BaseCache

  def initialize
    super
  end

  # Populates the cache from the file given, which should be a JSON
  # file as described in the class description.
  def load(cache_file)
    cache_fh =
      if File.exist?(cache_file)
        File.read(cache_file)
      else
        # create empty object
        File.open(cache_file, "w") { |f| f.write("{}") }
        File.read(cache_file)
      end

    loaded = JSON.load(cache_fh)
    @cache_file = cache_file
    @cache.clear
    @cache.merge! loaded
    @loaded_hash = @cache.hash

    # warn ">> loaded "+cache_file
    # Save ourselves at exit
    at_exit { self.save }
    
    return self
  end

  # Saves the cache to the file given, which will be a JSON
  # file as described in the class description.
  def save(cache_file = nil)
    cache_file ||= @cache_file
    # warn ">> saving if #{@loaded_hash} != #{@cache.hash} and #{cache_file} == nil"
    return if @loaded_hash == @cache.hash # nothing to do
    return if cache_file == nil # no file to save to
    # warn ">> saving"
    File.open(cache_file, "w") do |f|
      f.puts JSON.pretty_generate(@cache)
    end
    
    @loaded_hash = @cache.hash # update this
    @cache_file = cache_file # and this
    return self
  end

end
