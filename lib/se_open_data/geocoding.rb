require 'geocoder'
require 'se_open_data/utils/log_factory'

module SeOpenData
  # API for geocoding.
  #
  # Intended as a thin shim between the user code and the potentially
  # varied geocoder services and implementations we might support.
  #
  # Currently all geocoding is done using the Geocoder gem, but this
  # could change or need to be tweaked in the future.
  class Geocoding
    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default

    # A geocoding result.
    #
    # Currently just exposes what we use
    #
    # Allows access to the original result as a back-door
    class Result
      attr_reader :lat, :lng, :confidence, :original
      def initialize(original, lat, lng, confidence)
        @original, @lat, @lng, @confidence = [original, lat, lng, confidence]
      end

      # Returns a URI for this lat/lng location (based on openstreetmap.org)
      #
      # Used to refer to it as an entity when building queries.
      def osm_uri
        "https://www.openstreetmap.org/mlat=#{@lat}&mlong=#{@lng}"
      end
    end
    
    # Function which builds a geocoder lambda function
    #
    # lookup - indicates the type of geocoding service to
    # use. Currently passed verbatim to the 3rdparty class
    # Geocoder#search, therefore see that class for a list of valid
    # values.
    #
    # cache - an optional SeOpenData::Util::BaseCache derived class,
    # or some other object which suports the caching API required by
    # Geocoder#search.
    #
    # api_key - an optional API key, passed to Geocoder#search
    #
    # Returns a lambda function which calls the geocoding
    # service. This can be called with one argument: the address to
    # geocode.  It returns a Geocoding::Result instance, or nil if
    # there is no result returned.
    def build(lookup:, cache: nil, api_key: nil)

      Geocoder.configure(lookup: lookup, api_key: api_key, cache: cache, timeout: 10)

      return lambda {|address|
        Log.debug("geocoding: "+address)

        # Geocoder may not return the best result first - so find it.
        # Precompute the confidences...
        confidences = Geocoder.search(address).map do |result|
          [get_confidence(lookup, result), result]
        end
        # Find the result with the best confidence
        (confidence, result) = confidences.reduce do |best, result|
          result[0] > best[0]? result : best
        end
        # warn "#{confidence} <- #{confidences.map{|c| c[0] }.inspect}"
        if result == nil
          Log.info("geocoded '#{address}' to: no result")
          nil
        else
          Log.info("geocoded '#{address}' to: #{[result.latitude, result.longitude, confidence]}")
          return Result.new(
                   result,
                   result.latitude,
                   result.longitude,
                   confidence,
                 )
        end
      }
    end

    # Finds the confidence according to the lookup
    def get_confidence(lookup, result)
      case lookup
      when :geoapify
        (result.data.dig("properties","rank","confidence")*100).to_i
      when :mapbox
        (result.data.dig("relevance")*100).to_i
      when :nominatim
        nil # seems to be no confidence ranking
      else # Others not yet supported
        nil
      end
    end
    
  end
end
