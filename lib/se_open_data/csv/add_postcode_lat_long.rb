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
      input = File.open(infile, "r:bom|utf-8")
      output = File.open(outfile, "w")

      headers = to_schema.to_h
      postcode_field_id = :postcode
      postcode_header, country_header = headers.fetch_values(postcode_field_id, country_field_id)
      raise "missing #{postcode_field_id} field in schema" unless postcode_header
      raise "missing #{country_field_id} field in schema" unless country_header

      # IDs and header names of additional geocoded CSV fields to
      # populate (if replace_address is false, only these are
      # populated, else address_headers are too)
      new_headers = 
        subhash(headers,
                :geocontainer,
                :geocontainer_lat,
                :geocontainer_lon)

      # IDs and header names of address fields to write. Only required
      # if postcode_global_cache defined. 
      address_headers =
        subhash(headers,
                :street_address,
                :locality,
                :region,
                :postcode)
      
      csv_opts.merge!(headers: true)
      csv_in = ::CSV.new(input, **csv_opts)
      csv_out = ::CSV.new(output)

      # Geoapify API key required
      geocoder_standard = SeOpenData::CSV::Standard::GeoapifyStandard::Geocoder.new(api_key)

      # geocoded header names (and their mapping to keys of the
      # returned geocoder data hash).
      geocoder_headers = SeOpenData::CSV::Standard::GeoapifyStandard::Headers

      if use_ordinance_survey
        postcode_client = SeOpenData::RDF::OsPostcodeUnit::Client.new(lat_lng_cache)
      end
      
      global_postcode_client = SeOpenData::RDF::OsPostcodeGlobalUnit::Client.new(postcode_global_cache, geocoder_standard)

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
        postcode = row[postcode_header]
        country = row[country_header]
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
      
    ensure
      input.close
      output.close
    end
  end
end
