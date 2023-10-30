require 'digest'

module SeOpenData
  module Utils
# This class implements the basic in-memory hash based caching
# mechanism used by classes which can then implement the load/save
# mechanism.
#
# It is designed to be compatible with the caching API expected
# by the 3rd party `geocoder` gem
#
# The keys used by that gem are long URLs - which include the API key
# for the service in question. In order to shorten those, and
# obfuscate the keys, we use an MD5 hash of the key given.
class BaseCache

  # Constructor. Simply initialises an empty, unsaved cache.
  def initialize
    @cache = {}
  end

  # Performs a digest transform on a raw key to give the value we use
  # in the hash. See point about compacting/obfuscation in the class
  # description.
  def digest(key)
    Digest::MD5.hexdigest key
  end

  # Gets a value from its (undigested) key
  def [] (key)
    @cache[digest key]
  end

  # Stores a value given its (undigested) key
  def []= (key, val)
    @cache[digest key] = val
  end

  # Deletes a value given its (undigested) key
  def del(key)
    @cache.delete(digest key)
  end

  # Copies the content of another BaseCache.
  #
  # Mainly useful for converting one saved cache into another.
  #
  # Performs a clone of the underlying hash object. Will raise an
  # exception if the cache is not derived from that base class.
  def copy(cache)
    unless cache.is_a? SeOpenData::Utils::BaseCache
      raise "cannot copy anything not a SeOpenData::Utils::BaseCache"
    end
    @cache = cache.hash.clone
    return self
  end

  # Accessor for the underlying hash object storing the values in-memory
  def hash
    @cache
  end

  # Populates the cache from a storage location.
  #
  # The location is recorded, and used as the default to save back to.
  #
  # This method should be implemented by derived classes.
  def load(location)
    raise NotImplementedError
  end

  # Saves the cache back to a storage location (or the last used one, if unspecified)
  #
  # This method should be implemented by derived classes.
  def save(location = nil)
    raise NotImplementedError
  end
end
end
end
