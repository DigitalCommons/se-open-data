# coding: utf-8
module SeOpenData
  module CSV
    module Standard
      module GeoapifyStandard
        require "csv"
        require "httparty"
        require "json"
        require "cgi"
        require "normalize_country"
        require "se_open_data/initiative/rdf/config"
        require "se_open_data/rdf/os_postcode_unit"
        require "se_open_data/utils/progress_counter"
        require "se_open_data/utils/geocoding"

        Limit = 11000

        #map standard headers to geocoder headers
        Headers = {
          street_address: "street",
          locality: "city",
          region: "state",
          postcode: "postcode",
          country_name: "country",
          geocontainer_lat: "lat",
          geocontainer_lon: "lon",
          geocontainer: "geo_uri",
        }

        class Geocoder
          # @param api_key [String] the API key.
          def initialize(api_key)
            @api_key = api_key
            # Headers here should relate to the headers in standard
            @requests_made = 0
          end

          def make_geo_container(lat, long)
            "https://www.openstreetmap.org/?mlat=#{lat}&mlon=#{long}"
          end

          #standard way of getting new data
          def get_new_data(search_key, country)
            #make sure we are within limits
            if @requests_made > Limit
              raise "400 too many requests (raised from localhost)"
            end
            #check search key length
            #remove elements to cut it down to size
            # while search_key.length > 130
            #   temp = search_key.split(",")
            #   temp.pop
            #   search_key = temp.join(",")
            # end
            #return empty for unsensible key
            if search_key.length < 5
              return {}
            end
            #requests requirements
            #comma-separated
            #no names
            #include country
            #remove unneeded characters '/< etc..
            #remove unneeded address info
            uri_search_key = CGI.escape(search_key)
            url = "https://api.geoapify.com/v1/geocode/search?text=#{uri_search_key}&limit=1&apiKey=#{@api_key}"
            cn = NormalizeCountry(country, to: :alpha2)
            if cn
              url = "https://api.geoapify.com/v1/geocode/search?text=#{uri_search_key}&&filter=countrycode:#{cn.downcase}&limit=1&apiKey=#{@api_key}"
            end

            results = HTTParty.get(url)
            if results.code != 200
              raise "Failed to geocode search key: #{search_key} via #{url}: #{results.message}, #{results.parsed_response['message']}"
            end

            res_raw_json = JSON.parse(results.to_s)["features"]
            res_raw = (res_raw_json == nil || res_raw_json.length < 1) ? {} : res_raw_json[0]["properties"]

            #if no results
            if res_raw == nil || res_raw == {}
              return {}
            end
            res = res_raw
            #check if address headers exist + house number which is used below but not in the headers list
            all_headers = Headers.merge("k" => "house_number")
            all_headers.each { |k, v|
              #if the header doesn't exist create an empty one
              if !res.key?(v)
                res.merge!({ v => "" })
              end
            }
            #add road and house number (save to road) to make a sensible address
            res["street"] = res["street"] + " " + res["house_number"].to_s unless res["house_number"].to_s == ""
            res.merge!({ "geo_uri" => make_geo_container(res["lat"], res["lon"]) })
            @requests_made += 1
            return res
          end

          private

          # FIXME possibly unused?
          def _gen_geo_report(cached_entries_file, confidence_level = 0.25, gen_dir, generated_standard_file, headers_to_not_print)
            return unless File.exist?(cached_entries_file)

            # read in entries
            entries_raw = File.read(cached_entries_file)
            # is a map {key: properties}
            entries_json = JSON.load entries_raw

            # document initiatives that cannot be located (identified by)
            # does not have rank key
            no_entries_map = entries_json.select { |e, v| !v.has_key?("rank") }
            no_entries_array = []
            no_entries_headers = nil

            # then document the initiatives where the confidence level is below the passed confidence_level
            # identified by rank: {...,confidence:x,...} if rank exists
            low_confidence_map = entries_json.reject { |e, v| !v.has_key?("rank") }
              .select { |e, v| v["rank"]["confidence"] < confidence_level }
            low_confidence_array = []
            low_confidence_headers = nil

            # load standard file entries into map
            # match both maps to their entries
            client = SeOpenData::Utils::Geocoding::LookupCache
            addr_headers = Headers.keys.map { |a| SeOpenData::CSV::Standard::V1::Headers[a] }

            ::CSV.foreach(generated_standard_file, headers: true) do |row|
              # make this with row
              addr_array = []
              addr_headers.each { |header| addr_array.push(row[header]) if row.has_key? header }
              address = client.clean_and_build_address(addr_array)
              # if no cached address and the address was not added manually
              if row["Latitude"] && row["Latitude"] != ""
                # skip manual cases
              elsif no_entries_map.has_key? address
                no_entries_array.push row
                no_entries_headers = row.headers.reject { |h| headers_to_not_print.include?(h) } unless no_entries_headers
              elsif low_confidence_map.has_key? address
                row["confidence"] = low_confidence_map[address]["rank"]["confidence"]
                row["geocontainer_lat"] = low_confidence_map[address][Headers[:geocontainer_lat]]
                row["geocontainer_lon"] = low_confidence_map[address][Headers[:geocontainer_lon]]
                low_confidence_array.push row
                low_confidence_headers = row.headers.reject { |h| headers_to_not_print.include?(h) } unless low_confidence_headers
              end
            end

            # sort bad location
            low_confidence_array.sort! { |x, y| -(y["confidence"] <=> x["confidence"]) }

            no_location_file = File.join(gen_dir, "EntriesWithoutALocation.pdf")
            no_location_title = "Entries That Could Not be Geocoded"
            no_location_intro = "In this file we present the entries that could not be geocoded using the details described in each row.
            In total there are #{no_entries_array.length} entries without a location."

            bad_location_file = File.join(gen_dir, "LowConfidenceEntries.pdf")
            bad_location_title = "Entries That Are Geocoded With Low Confidence"
            bad_location_intro = "In this file we present the entries that are geocoded, but with a low confidence factor (below #{confidence_level}).
            In total there are #{low_confidence_array.length} entries which were geocoded with low confidence."

            # print documents
            verbose_fields = ["geocontainer_lat", "geocontainer_lon", "confidence"]
            doc = SeOpenData::Utils::ErrorDocumentGenerator.new("", "", "", "", [], false,
                                                                output_dir: gen_dir)
            if no_entries_array.length != 0
              doc.generate_document_from_row_array(no_location_title, no_location_intro,
                                                   no_location_file, no_entries_array, no_entries_headers)

              # write no-location entries to csv
              ::CSV.open(File.join(gen_dir, "no_location.csv"), "w") do |csv|
                csv << no_entries_headers.reject { |h| headers_to_not_print.include?(h) }
                no_entries_array.each { |r|
                  rowarr = []
                  no_entries_headers.each { |h| rowarr.push(r[h]) if (!headers_to_not_print.include? h) }
                  csv << rowarr
                }
              end
            end

            if low_confidence_array.length != 0
              doc.generate_document_from_row_array(bad_location_title, bad_location_intro,
                                                   bad_location_file, low_confidence_array, low_confidence_headers, verbose_fields)

              # write bad-location entries to csv
              ::CSV.open(File.join(gen_dir, "bad_location.csv"), "w") do |csv|
                csv << low_confidence_headers.reject { |h| headers_to_not_print.include?(h) }
                low_confidence_array.each { |r|
                  rowarr = []
                  low_confidence_headers.each { |h| rowarr.push(r[h]) if (!headers_to_not_print.include? h) }
                  csv << rowarr
                }
              end
            end
          end

          # FIXME possibly unused?
          def _gen_geo_location_confidence_csv(cached_entries_file, gen_dir, generated_standard_file, low_bar = 0.25)
            return unless File.exist?(cached_entries_file)
            system "mkdir", "-p", gen_dir
            # read in entries
            entries_raw = File.read(cached_entries_file)
            # is a map {key: properties}
            entries_json = JSON.load entries_raw
            addr_headers = Headers.keys.map { |a| SeOpenData::CSV::Standard::V1::Headers[a] }
            client = SeOpenData::Utils::Geocoding::LookupCache
            headers = nil

            ::CSV.open(File.join(gen_dir, "marked_confidence_entries.csv"), "w") do |csv|
              ::CSV.foreach(generated_standard_file, headers: true) do |row|
                unless headers
                  headers = row.headers
                  headers.push ("Confidence")
                  csv << headers
                end

                # make a list of manuals
                if row["Latitude"]
                  row["Confidence"] = "manual"
                  csv << row
                  next
                end

                # make this with row
                addr_array = []
                addr_headers.each { |header| addr_array.push(row[header]) if row.has_key? header }
                address = client.clean_and_build_address(addr_array)
                #if the key exists
                if !(entries_json.has_key? address) || !(entries_json[address].has_key?("rank"))
                  row["Confidence"] = "none"
                  csv << row
                  next
                end

                row["Geo Container Latitude"] = entries_json[address][Headers[:geocontainer_lat]]
                row["Geo Container Longitude"] = entries_json[address][Headers[:geocontainer_lon]]
                conf = entries_json[address]["rank"]["confidence"].to_f
                case
                when conf < low_bar
                  row["Confidence"] = "low"
                else
                  row["Confidence"] = "no comments"
                end
                csv << row
              end
            end
          end
        end
      end
    end
  end
end
