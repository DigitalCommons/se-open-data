def uk_postcode?(s)
  uk_postcode_regex = /([Gg][Ii][Rr] 0[Aa]{2})|((([A-Za-z][0-9]{1,2})|(([A-Za-z][A-Ha-hJ-Yj-y][0-9]{1,2})|(([A-Za-z][0-9][A-Za-z])|([A-Za-z][A-Ha-hJ-Yj-y][0-9][A-Za-z]?))))\s?[0-9][A-Za-z]{2})/
  uk_postcode_regex.match(s)
end

# OX1 = 51.75207,-1.25769
# OX2 =

module SeOpenData
  module CSV
    require "se_open_data/csv/schemas"
    require "se_open_data/csv/standard"

    # The latest output schema
    StdSchema = SeOpenData::CSV::Schemas::Versions[-1]

    def self.subhash(hash, *keys)
      keys = keys.select { |k| hash.key?(k) }
      Hash[keys.zip(hash.values_at(*keys))]
    end
    
    # Fill out the geocoding fields in a CSV
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
    # @param infile [String] A file path to read from
    # @param outfile [String] A file path to write to
    # @param api_key [String] An API key to use for the global geocoder, optional if
    # postcode_global_cache not set
    # @param lat_lng_cache [String] The path to a JSON file into which to cache postcode geolocations
    # @param postcode_global_cache [String] The path to JSON file into which to cache global
    # @param to_schema [SeOpenData::CSV::Schema] instance defining the output schema
    # @param country_field_id [String] The field id to use as the country component of the lookup
    # defaults to :country_name for historical backward compatibility.
    # address geolocations
    # @param replace_address [Boolean] If true addresses in the CSV are replaced with
    # the resolved address from the geocoder. Defaults to false.
    # @param csv_opts [Hash] options to pass to CSV when parsing input_io (in addition to `headers: true`)
    # @param use_ordinance_survey [Boolean] set true to use ordinance survey to geocode UK postcodes    
    def self.add_postcode_lat_long(infile:, outfile:,
                                   api_key:, lat_lng_cache:, postcode_global_cache:,
                                   to_schema: StdSchema,
                                   country_field_id: :country_name,
                                   replace_address: false, csv_opts: {},
                                   use_ordinance_survey: false)
      add_postcode_lat_long2(
        infile: infile, outfile: outfile,
        api_key: api_key,
        lat_lng_cache: lat_lng_cache, postcode_global_cache: postcode_global_cache,
        to_schema: to_schema,
        country_field_id: country_field_id,
        use_ordinance_survey: use_ordinance_survey,
        replace_address: replace_address,
        csv_opts: csv_opts,
      )
    end

    def self.add_postcode_lat_long2(infile:, outfile:, api_key:,
                                    country_field_id: :country_name,
                                    lat_lng_cache:, postcode_global_cache:,
                                    to_schema:, use_ordinance_survey: true,
                                    replace_address: false,
                                    csv_opts: {})
      input = File.open(infile, "r:bom|utf-8")
      output = File.open(outfile, "w")

      headers = to_schema.to_h
      postcode_field_id = :postcode
      postcode_header, country_header = headers.fetch_values(postcode_field_id, country_field_id)
      raise "missing #{postcode_field_id} field in schema" unless postcode_header
      raise "missing #{country_field_id} field in schema" unless country_header
      
      SeOpenData::CSV._add_postcode_lat_long(
        input,
        output,
        postcode_header,
        country_header,
        subhash(headers,
                :geocontainer,
                :geocontainer_lat,
                :geocontainer_lon),
        lat_lng_cache,
        csv_opts,
        postcode_global_cache,
        subhash(headers,
                :street_address,
                :locality,
                :region,
                :postcode),
        replace_address,
        api_key,
        use_ordinance_survey
      )
    ensure
      input.close
      output.close
    end

    # Transforms a CSV file, adding latitude and longitude fields
    # obtained by geocoding a postcode field.
    #
    # - should take in which headers to change with which standard STANDARD_HEADERS from global
    # - should have boolean weather to change addresses
    # - postcode unit cache is legacy?
    #
    # TODO: this is becoming a noodle factory, fix and clean it
    #
    # TODO: abstract away so that you only pass the standard and the io and it does the work for you
    #
    # @param input_io [IO, File] file or stream to read CSV data from
    # @param output_io [IO, File] file or stream to write CSV data to
    # @param input_csv_postcode_header [String] header of input CSV field containing postcodes
    # @param input_country_header [String] header of input CSV field containing country names
    # @param new_headers [Hash<Symbol,String>] IDs and header names of additional geocoded CSV
    # fields to populate (if replace_address is false, only these are populated, else
    # address_headers are too)
    # @param postcodeunit_cache [String] JSON file where OS postcode unit results are cached (passed to
    # {SeOpenData::RDF::OsPostcodeUnit::Client})
    # @param csv_opts [Hash] options to pass to CSV when parsing input_io (in addition to `headers: true`)
    # @param global_postcode_cache [String] optional path to a JSON file where all the postcodes are kept (passed to {SeOpenData::RDF::OsPostcodeGlobalUnit::Client}). If absent, no global geocoding is done, so geocoder_standard need not be set.
    # @param address_headers [Hash<Symbol,String>] IDs and header names of address fields to write. Only required if global_postcode_cache defined.
    # @param replace_address [Boolean] set to true if we should replace the current address headers && set to "force" if we should replace the headers with whatever the geocoder finds (i.e.replace the field even if the geocoder finds nothing). Only required if global_postcode_cache defined.
    # @param geocoder_headers [Hash<Symbol,String>] defines geocoded header names (and their
    # mapping to keys of the returned geocoder data hash). Only required if global_postcode_cache defined.
    # @param geocoder_standard [#get_new_data(search_key,country)] a geocoder, only used if global_postcode_cache defined.
    # @param use_ordinance_survey [Boolean] set true to use ordinance survey to geocode UK postcodes
    def self._add_postcode_lat_long(
      input_io,
      output_io,
      input_csv_postcode_header,
      input_country_header,
      new_headers,
      postcodeunit_cache,
      csv_opts = {},
      global_postcode_cache,
      address_headers,
      replace_address,
      api_key,
      use_ordinance_survey
    )
      csv_opts.merge!(headers: true)
      csv_in = ::CSV.new(input_io, **csv_opts)
      csv_out = ::CSV.new(output_io)

      geocoder_standard = nil
      geocoder_headers = nil
      # Geoapify API key required
      geocoder_standard = SeOpenData::CSV::Standard::GeoapifyStandard::Geocoder.new(api_key)
      geocoder_headers = SeOpenData::CSV::Standard::GeoapifyStandard::Headers

      if use_ordinance_survey
        postcode_client = SeOpenData::RDF::OsPostcodeUnit::Client.new(postcodeunit_cache)
      end
      
      global_postcode_client = SeOpenData::RDF::OsPostcodeGlobalUnit::Client.new(global_postcode_cache, geocoder_standard)

      #add global postcode
      headers = nil
      row_count = csv_in.count
      csv_in.rewind
      prog_ctr = SeOpenData::Utils::ProgressCounter.new("Fetching geodata... ", row_count, $stderr)
      csv_in.each do |row|
        unless headers
          headers = row.headers + new_headers.values.reject { |h| row.headers.include? h }
          csv_out << headers
        end
        prog_ctr.step
        # Only run if matches uk postcodes
        postcode = row[input_csv_postcode_header]
        country = row[input_country_header]
        if use_ordinance_survey && uk_postcode?(postcode) # UCOMMENT TO USE ORDINANCE SURVEY FOR UK POSTCODE GEOLOCATION
          pcunit = postcode_client.get(postcode)
          loc_data = {
            geocontainer: pcunit ? pcunit[:within] : nil,
            geocontainer_lat: pcunit ? pcunit[:lat] : nil,
            geocontainer_lon: pcunit ? pcunit[:lng] : nil,
            country_name: "United Kingdom",
          }
          new_headers.each { |k, v|
            row[v] = loc_data[k]
          }
        elsif global_postcode_client #geocode using global geocoder
          #standardize the address if indicated

          # This will contain the headers of fields to replace with geocoded data
          headersToUse = {}

          if replace_address != false
            # include address_fields
            headersToUse = new_headers.merge(address_headers) # new_headers plus address_headers
          else
            # just the input fields
            headersToUse = new_headers 
          end

          # Build an address array
          address = address_headers.collect { |k, v| row[v] }

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
          pcunit = global_postcode_client.get(address, country) #assigns both address_headers field

          if pcunit == nil
            csv_out << row
            next
          end
          
          #only replace information about address, do not delete information
          #or maybe you should delete it when you want to compare locations?
          if replace_address == "force"
            headersToUse.each do |k, v|
              row[v] = pcunit[geocoder_headers[k]]
            end
          else 
            headersToUse.each do |k, v|
              if pcunit[geocoder_headers[k]].to_s != ""
                row[v] = pcunit[geocoder_headers[k]]
              end
            end
          end
        end

        csv_out << row
      end

      if global_postcode_client
        global_postcode_client.finalize(0)
      end
    end
  end
end
