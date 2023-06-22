require "csv"
require "json"
require "pstore"
require "normalize_country"
#require "se_open_data/utils/deployment"
require "se_open_data/utils/log_factory"
require "se_open_data/utils/postcode_uk"

module SeOpenData::Utils::Geocoding

  class JsonCache
    Log = SeOpenData::Utils::LogFactory.default
    
    def initialize(filename)
      @file = filename
      @dirty = false # will be set true if the cache is changed.
      
      if File.exist?(filename)
        @cache = JSON.load(File.read(filename))
      else
        @cache = {}
        # create empty object
        File.open(filename, "w") { |f| f.write("{}") }
      end
      
    end

    def keys
      @cache.keys
    end

    def key?(key)
      @cache.key?(key)
    end

    def get(key)
      @cache[key]
    end

    def add(key, value)
      @dirty = true
      @cache[key] = value;
    end

    def finalize(object_id)
      #save cache if it has been updated
      if @dirty
        Log.info "SAVING NEW CACHE"
        File.open(@csv_cache_file, "w") do |f|
          f.puts JSON.pretty_generate(@cache)
        end
      end
    end

  end
  
  class PstoreCache
    Log = SeOpenData::Utils::LogFactory.default
    
    def initialize(filename)
      @file = filename
      @pstore = PStore.new(filename)
    end

    def keys
      @pstore.transaction { @pstore.roots }
    end

    def key?(key)
      @pstore.transaction do
        @pstore.root?(key)
      end
    end

    def get(key)
      @pstore.transaction do
        @pstore[key]
      end
    end

    def add(key, value)
      warn ">> add #{key}: #{value}"
      @pstore.transaction do
        @pstore[key] = value;
      end
    end

    def finalize(object_id)
    end

  end
  
  class LookupCache
    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default
    PostcodeUk = SeOpenData::Utils::PostcodeUk
    
    attr_accessor :cache
    attr_accessor :initial_cache
    attr_reader :geocoder
    attr_reader :csv_cache_file

    def initialize(csv_cache_filename, geocoder_standard)
      @geocoder = geocoder_standard
      @cache = PstoreCache.new(csv_cache_filename+'.pstore')
    end

    # @param address_array - an array that contains the address
    # @returns - a query for looking up the address
    def clean_and_build_address(address_array)
      return nil unless address_array
      address_array.reject! { |addr| addr == "" || addr == nil }
      address_array.map! { |addr| PostcodeUk.valid?(addr) ? addr.gsub(/[!@#$%^&*-]/, " ") : addr } # remove special characters

      # Expand 2-letter country codes, hackily (best effort, this is all hacky already)
      address_array.map! do |addr|
        addr.match(/^[A-Z][A-Z]$/)? NormalizeCountry(addr, to: :short) : addr
      end
      search_key = address_array.join(", ")
      Log.info "Geocoding: #{search_key}";
      return nil unless search_key
      return search_key
    end

    # Has to include standard cache headers or returns nil
    def get(address_array, country)
      begin
        #clean entry

        search_key = clean_and_build_address(address_array)
        return nil unless search_key

        cached_entry = {}
        #if key exists get it from cache
        if @cache.key?(search_key)
          cached_entry = @cache.get(search_key)
        else
          #else get address using client and append to cache
          cached_entry = @geocoder.get_new_data(search_key, country)
          @cache.add(search_key, cached_entry)
          @dirty = true
        end

        return nil if cached_entry.empty?

        #return entry found in cache or otherwise gotten through api
        cached_entry
      rescue StandardError => msg
        Log.error msg
        #save due to crash
        @cache.finalize(0)
        #if error from client-side or server, stop
        if msg.message.include?("4") || msg.message.include?("5")
          raise msg
        end
        #continue to next one otherwise
        return nil
      end
    end

    def finalize(oid)
      @cache.finalize(oid)
    end
  end
end
