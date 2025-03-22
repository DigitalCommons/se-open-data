require 'se_open_data/utils/base_cache'
require 'fileutils'

# This is an implementation of SeOpenData::Utils::BaseCache which
# is backed by directory containing plain text files, one per key.
#
# The directory should have zero or more .txt files with the base name
# corresponding to the (digested) key of each entry. The content of
# the file is the value, verbatim.
#
# When loading, directories are ignored. When saving, any files or
# directories not corresponding to keys in the hash are removed.
#
# It adds an `at_exit` hook to save the cache data even if it is not
# done explicitly.
class SeOpenData::Utils::FileCache < SeOpenData::Utils::BaseCache
  def initialize
    super
  end
  
  # Populates the cache from the directory given, which should contain
  # text files as described in the class description.
  #
  # The directory will be created if it does not exist. It is recorded
  # for use as the default for the next save.
  def load(cache_dir)
    if !Dir.exist?(cache_dir)
      FileUtils.mkdir_p(cache_dir)
    end

    @cache.clear
    # warn "load "+cache_dir
    Dir.foreach(cache_dir) do |name|
      next if name == '.' or name == '..'
      path = File.join(cache_dir, name)
      next if !File.file? path
      next if !name.end_with? '.txt'
      # warn "loading "+name+"=>"+name[0..-5].to_s
      content = IO.read(path)
      @cache[name[0..-5]] = content
    end
    
    @cache_dir = cache_dir
    @loaded_hash = @cache.hash

    # warn ">> loaded "+cache_dir
    # Save ourselves at exit
    at_exit { self.save }
    
    return self
  end

  # Saves the cache to the directory given, which should contain text
  # files as described in the class description. If no directory is
  # given, the last directory loaded or saved to is used. If neither
  # is defined nothing is done.
  #
  # When saving, the directory will be created if it does not exist yet.
  #
  # Any files or directories not corresponding the keys of the cache
  # will be removed.
  def save(cache_dir = nil)
    cache_dir ||= @cache_dir
    #warn ">> saving if #{@loaded_hash} != #{@cache.hash} and #{cache_dir} == nil"
    return if @loaded_hash == @cache.hash # nothing to do
    return if cache_dir == nil # no dir to save to
    
    if !Dir.exist?(cache_dir)
      FileUtils.mkdir_p(cache_dir)
    end
    
    # warn ">> saving"
    # Delete unused files
    Dir.foreach(cache_dir) do |name|
      next if name == '.' or name == '..'
      path = File.join(cache_dir, name)
      next if Dir.exist? path # skip directories
      # warn "unlink? #{path} -> #{File.exist? path} and #{!@cache.has_key? name}"
      if File.exist? path and !@cache.has_key? name
        File.unlink(path)
      end
    rescue => e
      warn "Warning: failed to delete unused file: #{path}: #{e}"
    end

    # Save the content
    @cache.each_pair do |key, content|
      path = File.join(cache_dir, key+'.txt')
      IO.write(path, content)
    rescue => e
        warn "Warning: failed to create cache file: #{path}: #{e}"      
    end
    
    @loaded_hash = @cache.hash # update this
    @cache_dir = cache_dir # and this
    return self
  end

end
