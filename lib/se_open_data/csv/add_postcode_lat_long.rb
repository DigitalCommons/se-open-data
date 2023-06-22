

module SeOpenData
  module CSV
    require "se_open_data/csv/schemas"
    require "se_open_data/csv/standard"
    require "se_open_data/utils/postcode_uk"
    require "se_open_data/utils/geocoding"

    PostcodeUk = SeOpenData::Utils::PostcodeUk
    
    
    # The latest output schema
    StdSchema = SeOpenData::CSV::Schemas::Versions[-1]
    
    def self.subhash(hash, *keys)
      keys = keys.select { |k| hash.key?(k) }
      Hash[keys.zip(hash.values_at(*keys))]
    end
    
    # Common code for geocoding a standard CSV file.
    #
    # The to_schema parameter defines the actual headers to expect.
    # They are referred to using IDs, which are symbols, and act as
    # convenient short names.
    # 
    # Certain fields IDs are expected to be present in the schema.
    # - street_address
    # - locality
    # - region
    # - geocontainer
    # - geocontainer_lat
    # - geocontainer_lon
    # 
    # These fields IDs can be defined in the constructor (as they are known to vary),
    # but have essentially the obvious role in the adderss
    # - postcode (postcode_field_id)
    # - country name/id (country_field_id)
    #
    # They will be inserted into the address in the appropriate place.
    #
    # Derived classes may expect other fields in addition to these.
    #
    # This is not a full implementation, by default it makes no
    # transformation.  Derived classes should override transform_row /
    # transform_rows as needed to perform the actual geocoding
    # transform which adds values to the Latitude and Longitude, Geo
    # Container, Geo Container Latitude and Geo Container Longitude
    # fields
    #
    # Typical usage of derived classes.:
    #
    #     g = DerivedGeocoder.new(to_schema: schema, 
    #         to_schema: to_schema,
    #         country_field_id: country_field_id,
    #         replace_address: replace_address,
    #         csv_opts: csv_opts,
    #         # ... other params
    #     )
    # 
    #     g.transform(input_file, output_file)
    #
    class BaseGeocoder
      
      # @param to_schema [SeOpenData::CSV::Schema] instance defining the output schema
      # @param country_field_id [Symbol] The id of the CSV schema field to use for the
      # country component of the address lookup.
      # Defaults to :country_name for historical backward compatibility.
      # @param postcode_field_id [Symbol] The id of the CSV schema field to use for the
      # postcode component of the address lookup.
      # Defaults to :postcode for historical backward compatibility.
      # @param replace_address [Boolean|"force"] If true address fields in the output CSV 
      # are replaced with the resolved address from the geocoder. If "force", this is done even if the
      # geocoder finds nothing. Defaults to false, and is ignored if use_ordinance_survey is true
      # (when replacements don't happen)
      # @param csv_opts [Hash] options to pass to CSV when parsing input_io
      # (in addition to `headers: true`)
      def initialize(
            to_schema:,
            postcode_field_id:,
            country_field_id:,
            replace_address:,
            csv_opts: {}
          )
        @to_schema = to_schema
        headers = to_schema.to_h
        @country_field_id = country_field_id
        @postcode_field_id = postcode_field_id
        @postcode_field_id = postcode_field_id
        @postcode_header, @country_header = headers.fetch_values(postcode_field_id, country_field_id)
        raise "missing #{postcode_field_id} field in schema" unless @postcode_header
        raise "missing #{country_field_id} field in schema" unless @country_header

        @replace_address = replace_address
        @csv_opts = csv_opts
        
        # IDs and header names of address fields to write. Only required
        # if postcode_global_cache defined. 
        @address_headers =
          subhash(@to_schema.to_h,
                  :street_address,
                  :locality,
                  :region,
                  postcode_field_id)

        # IDs and header names of additional geocoded CSV fields to
        # populate (if replace_address is false, only these are
        # populated, else address_headers are too)
        @new_headers = 
          subhash(headers,
                  :geocontainer,
                  :geocontainer_lat,
                  :geocontainer_lon)

        csv_opts.merge!(headers: true)
      end

      # @param infile [IO, File] file or stream to read CSV data from
      # @param oufile [IO, File] file or stream to write CSV data to      
      def transform(infile, outfile)
        input = File.open(infile, "r:bom|utf-8")
        output = File.open(outfile, "w")

        csv_in = ::CSV.new(input, **@csv_opts)
        csv_out = ::CSV.new(output)

        transform_rows(csv_in, csv_out)
        
      ensure
        input.close
        output.close
      end

      # Transforms a sequence of CSV rows
      #
      # @param csv_in The input CSV to read from
      # @param csv_out The output CSV to write to
      def transform_rows(csv_in, csv_out)
        headers = nil
        row_count = csv_in.count
        csv_in.rewind
        prog_ctr = SeOpenData::Utils::ProgressCounter.new("Fetching geodata... ", row_count, $stderr)

        csv_in.each do |row|
          unless headers
            headers = row.headers + @new_headers.values.reject { |h| row.headers.include? h }
            csv_out << headers
          end

          prog_ctr.step

          transform_row(row)

          csv_out << row
        end

        if @global_postcode_client
          @global_postcode_client.finalize(0)
        end

      end

      # Transforms a single CSV row instance.
      def transform_row(row)
        # no op
      end

      private

      # Takes a hash and returns a new hash with just the keys named
      # mapped to the values they had in the original.
      def subhash(hash, *keys)
        keys = keys.select { |k| hash.key?(k) }
        Hash[keys.zip(hash.values_at(*keys))]
      end
    end

    # Geocodes a standard CSV file using the Geoapify geocoder,
    class GeoapifyGeocoder < BaseGeocoder

      # Constructor
      #
      # Parameters as for BaseGeocoder.new, plus:
      #
      # @param api_key [String] An API key to use for the global geocoder, optional if
      # postcode_global_cache not set
      # @param cache_file [String] The path to a JSON file into which to cache 
      # geolocations
      def initialize(
            api_key:,
            replace_address: false,
            to_schema: StdSchema,
            postcode_field_id: :postcode,
            country_field_id: :country_name,
            cache_file:,
            csv_opts: {}
          )
        super(
          to_schema: to_schema,
          replace_address: replace_address,
          postcode_field_id: postcode_field_id,
          country_field_id: country_field_id,
          csv_opts: csv_opts,
        )

        # Geoapify API key required
        geocoder_standard = SeOpenData::CSV::Standard::GeoapifyStandard::Geocoder.new(api_key)
        
        # geocoded header names (and their mapping to keys of the
        # returned geocoder data hash).
        @geocoder_headers = SeOpenData::CSV::Standard::GeoapifyStandard::Headers
        
        @global_postcode_client = SeOpenData::Utils::Geocoding::LookupCache.new(
          cache_file, geocoder_standard
        )
      end

      def transform_row(row)
        country = row[@country_header]

        # This will contain the headers of fields to replace with geocoded data
        headersToUse = 
          if @replace_address != false
            # include address_fields
            @new_headers.merge(@address_headers) # new_headers plus address_headers
          else
            # just the input fields
            @new_headers 
          end

        # Build an address array
        address = @address_headers.collect { |k, v| row[v] }

        # Add the country, for consistency with original
        # implementation, This implementation omits :country_name
        # from address_headers, which defines what fields to update,
        # so that the country name isn't overwritten with an
        # (empirically inconsistent, non-unique) country name from
        # the geocoder. The country name should stay as-is (what
        # sense does it make for an address with the country "Czech
        # Republic" to be changed to one in "Czechia" by geocoding,
        # especially if other addresses geocode to "Czech
        # Republic"?)
        # See https://github.com/SolidarityEconomyAssociation/dotcoop-project/issues/10
        address.push(country)

        #return with the headers i want to replace
        pcunit = @global_postcode_client.get(address, country) #assigns both address_headers field

        if pcunit == nil
          return
        end
        
        #only replace information about address, do not delete information
        #or maybe you should delete it when you want to compare locations?
        if @replace_address == "force"
          headersToUse.each do |k, v|
            row[v] = pcunit[@geocoder_headers[k]]
          end
        else 
          headersToUse.each do |k, v|
            if pcunit[@geocoder_headers[k]].to_s != ""
              row[v] = pcunit[@geocoder_headers[k]]
            end
          end
        end      
      end
    end

    # Geocodes a standard CSV file using the OS postcode geocoder,
    # falling back to the Geoapify coder.
    class OsGeocoder < GeoapifyGeocoder

      # Constructor
      #
      # Parameters as for GeoapifyGeocoder.new, plus:
      #
      # @param postcode_cache_file [String] The path to a JSON file into which to cache OS postcode
      # geolocations
      # @param geoapify_cache_file [String] The path to JSON file into which to cache geoapify
      # geolocations (passed to GeoapifyGeocoder's cache_file parameter)
      def initialize(
            api_key:,
            replace_address: false, 
            to_schema: StdSchema,
            postcode_field_id: :postcode,
            country_field_id: :country_name,
            geoapify_cache_file:,
            postcode_cache_file:,
            csv_opts: {}
          )
        super(
          api_key: api_key,
          to_schema: to_schema,
          replace_address: replace_address,
          postcode_field_id: postcode_field_id,
          country_field_id: country_field_id,
          cache_file: geoapify_cache_file,
          csv_opts: csv_opts,
        )

        @postcode_client = SeOpenData::RDF::OsPostcodeUnit::Client.new(postcode_cache_file)
      end
      
      def transform_row(row)
        postcode = row[@postcode_header]
        
        if PostcodeUk.valid?(postcode)
          pcunit = @postcode_client.get(postcode)
          loc_data = {
            geocontainer: pcunit ? pcunit[:within] : nil,
            geocontainer_lat: pcunit ? pcunit[:lat] : nil,
            geocontainer_lon: pcunit ? pcunit[:lng] : nil,
            @country_field_id => "United Kingdom" # FIXME this is hardwired ... might be UK?
          }
          @new_headers.each { |k, v|
            row[v] = loc_data[k]
          }

        else  #geocode using global geocoder
          super

        end

        return # nothing
      end

    end
    
    # Transforms a CSV file, adding latitude and longitude fields
    # obtained by geocoding a postcode field.
    #
    # Assumes the input and output CSV uses the schema
    # `to_schema`. Reads the address from the input fields with id
    # `:street_address`, `:locality`, `:region` and `:postcode`.
    # Writes the latitude and longitude to the output fields
    # `:geocontainer_lat` and `:geocontainer_lon` Also writes a
    # geolocation URL into `:geocontainer`.
    #
    # If postcode_global_cache is undefined, only postcode lookup
    # is done.
    #
    # If the api_key and postcode_global_cache parameters are set,
    # then if the postcode is not present or not a valid UK
    # postcode, it will attempt a global geocoding of the address.
    #
    # @param input [IO, File] file or stream to read CSV data from
    # @param output [IO, File] file or stream to write CSV data to
    # @param api_key [String] An API key to use for the global geocoder, optional if
    # postcode_global_cache not set
    # @param lat_lng_cache [String] The path to a JSON file into which to cache OS postcode
    # geolocations
    # @param postcode_global_cache [String] The path to JSON file into which to cache global
    # address geolocations
    # @param to_schema [SeOpenData::CSV::Schema] instance defining the output schema
    # @param country_field_id [Symbol] The id of the CSV schema field to use for the
    # country component of the address lookup.
    # Defaults to :country_name for historical backward compatibility.
    # @param postcode_field_id [Symbol] The id of the CSV schema field to use for the
    # postcode component of the address lookup.
    # Defaults to :postcode for historical backward compatibility.
    # @param replace_address [Boolean|"force"] If true address fields in the output CSV 
    # are replaced with the resolved address from the geocoder. If "force", this is done even if the
    # geocoder finds nothing. Defaults to false, and is ignored if use_ordinance_survey is true
    # (when replacements don't happen)
    # @param csv_opts [Hash] options to pass to CSV when parsing input_io
    # (in addition to `headers: true`)
    # @param use_ordinance_survey [Boolean] set true to use ordinance survey to geocode UK postcodes 
    def self.add_postcode_lat_long(infile:, outfile:,
                                   api_key:, lat_lng_cache:, postcode_global_cache:,
                                   to_schema: StdSchema,
                                   country_field_id: :country_name,
                                   replace_address: false, csv_opts: {},
                                   use_ordinance_survey: false)
      geocoder =
        if use_ordinance_survey
          OsGeocoder.new(
            api_key: api_key,
            geoapify_cache_file: postcode_global_cache,
            postcode_cache_file: lat_lng_cache,
            to_schema: to_schema,
            country_field_id: country_field_id,
            replace_address: replace_address,
            csv_opts: csv_opts
          )
        else
          GeoapifyGeocoder.new(
            api_key: api_key,
            cache_file: postcode_global_cache,
            to_schema: to_schema,
            country_field_id: country_field_id,
            replace_address: replace_address,
            csv_opts: csv_opts
          )
        end
          
      geocoder.transform(infile, outfile)
        
    end    

  end
end
