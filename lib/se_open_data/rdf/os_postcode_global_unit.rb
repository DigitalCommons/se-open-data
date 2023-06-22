require "csv"
require "json"
require "normalize_country"
require_relative "cache"
require "se_open_data/utils/deployment"
require "se_open_data/utils/log_factory"

module SeOpenData
  module RDF
    module OsPostcodeGlobalUnit
      class Client
        # Create a log instance
        Log = SeOpenData::Utils::LogFactory.default
        
        attr_accessor :cache
        attr_accessor :initial_cache
        attr_reader :geocoder
        attr_reader :csv_cache_file

        def initialize(csv_cache_filename, geocoder_standard)
          @geocoder = geocoder_standard
          @csv_cache_file = csv_cache_filename
          #load cache into memory (probably needs to be i/o in the future)
          csv_cache_f = nil

          if File.exist?(csv_cache_file)
            csv_cache_f = File.read(csv_cache_file)
          else
            # create empty object
            File.open(csv_cache_file, "w") { |f| f.write("{}") }
            csv_cache_f = File.read(csv_cache_file)
          end

          @cache = JSON.load csv_cache_f
          @dirty = false # will be set true if the cache is changed.
          
          #ObjectSpace.define_finalizer(self, method(:finalize))#make sure this works throughout the versions
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

        def self.uk_postcode?(s)
          uk_postcode_regex = /([Gg][Ii][Rr] 0[Aa]{2})|((([A-Za-z][0-9]{1,2})|(([A-Za-z][A-Ha-hJ-Yj-y][0-9]{1,2})|(([A-Za-z][0-9][A-Za-z])|([A-Za-z][A-Ha-hJ-Yj-y][0-9][A-Za-z]?))))\s?[0-9][A-Za-z]{2})/
          uk_postcode_regex.match(s)
        end

        # @param address_array - an array that contains the address
        # @returns - a query for looking up the address
        def self.clean_and_build_address(address_array)
          return nil unless address_array
          address_array.reject! { |addr| addr == "" || addr == nil }
          address_array.map! { |addr| uk_postcode?(addr) ? addr.gsub(/[!@#$%^&*-]/, " ") : addr } # remove special characters

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

            search_key = Client.clean_and_build_address(address_array)
            return nil unless search_key

            cached_entry = {}
            #if key exists get it from cache
            if @cache.key?(search_key)
              cached_entry = @cache[search_key]
            else
              #else get address using client and append to cache
              cached_entry = @geocoder.get_new_data(search_key, country)
              @cache.merge!({ search_key => cached_entry })
              @dirty = true
            end

            return nil if cached_entry.empty?

            #return entry found in cache or otherwise gotten through api
            cached_entry
          rescue StandardError => msg
            Log.error msg
            #save due to crash
            finalize(0)
            #if error from client-side or server, stop
            if msg.message.include?("4") || msg.message.include?("5")
              raise msg
            end
            #continue to next one otherwise
            return nil
          end
        end
      end
    end
  end
end
