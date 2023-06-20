require 'se_open_data/config'
require 'se_open_data/utils/log_factory'
require 'se_open_data/utils/password_store'
require 'se_open_data/csv/add_postcode_lat_long'
require 'se_open_data/csv/geoapify_standard'
require 'se_open_data/csv/schema'
require 'se_open_data/csv/schema/types'
require 'csv'

module SeOpenData
  module CSV
    module Converter
      # Converts generic SSE initiative data
      #
      # This needs to be a schema whose fields are a superset of LimeSurveyCore
      # @see SeOpenData::CSV::Schemas::LimeSurveyCore
      #
      module LimeSurveyCore
        # Create a log instance
        Log = SeOpenData::Utils::LogFactory.default

        # A convenient alias...
        Types = SeOpenData::CSV::Schema::Types
        
        # Sometimes a single column can take values that are in fact a
        # list.  So we need to know the character used to separate the
        # items in the list.  For example, in the legal_form column,
        # we might have an initiative that is both a 'Cooperative' and
        # a 'Company', the cell would then have the value
        # "Cooperative;Company"
        SubFieldSeparator = ";"
        
        # This creates a generic converter for mapping incoming LimeQuery data
        # with the specified incoming schema into the standard schema.
        #
        # The incoming schema must have all the fields and primary keys
        # defined by LimeSurveyCore.
        #
        # The case-specific logic that maps the input field data is
        # defined in the do-block. It will be wrapped in a loop which
        # reads the input file and writes the output file. See the
        # documentation for {SeOpenData::CSV::Schema.converter}.
        #
        # The response data downloaded from limesurvey via the API appears
        # to be different to that downloaded previously.
        # - semi-colon delimited, not comma delimited
        # - 'activities' field contains a identifier, not a human-readable phrase.
        #
        # The delimiter appears to be configurable in the web download, but not in the API.
        # https://bugs.limesurvey.org/view.php?id=13747
        def self.mk_converter(from_schema:,
                              to_schema:,
                              input_csv_opts: {col_sep: ';', skip_blanks: true})
          from_schema.assert_superset_of SeOpenData::CSV::Schemas::LimeSurveyCore::Latest
          
          return SeOpenData::CSV::Schema.converter(
                   from_schema: from_schema,
                   to_schema: to_schema,
                   input_csv_opts: input_csv_opts
                 ) do | # These parameters match source schema field ids
                        id:,
                        name:,
                        address_a:,
                        address_b:,
                        address_c:,
                        locality:,
                        postcode:,
                        location:,
                        email:,
                        phone:,
                        website:,
                        facebook:,
                        twitter:,
                        description:,
                        activity:,
                        approved:,
                        community_group:,
                        non_profit:,
                        social_enterprise:,
                        charity:,
                        company:,
                        workers_coop:,
                        housing_coop:,
                        consumer_coop:,
                        producer_coop:,
                        stakeholder_coop:,
                        community_interest_company:,
                        community_benefit_society:,
                        arts:,
                        campaigning:,
                        community:,
                        education:,
                        energy:,
                        food:,
                        goods_services:,
                        health:,
                        housing:,
                        money:,
                        nature:,
                        reuse:,
#                        agriculture:,
#                        industry:,
#                        utilities:,
#                        transport:,
                        **rest
                        |
                        # A mapping to the target schema field ids

                        # Don't import this initiative if it isn't approved
                        next unless approved&.downcase == 'yes'

                        (latitude, longitude) = [*location.to_s.split(';'), '', ''].collect &:strip
                        {
                          id: id,
                          name: name,
                          description: description,
                          organisational_structure: organisational_structure_label(
                            community_group, non_profit, social_enterprise, charity,
                            company, workers_coop, housing_coop, consumer_coop,
                            producer_coop, stakeholder_coop,
                            community_interest_company, community_benefit_society
                          ),
                          primary_activity: primary_activity_label(activity),
                          activities: secondary_activity_labels(
                            arts, campaigning, community,
                            education, energy, food, goods_services,
                            health, housing, money, nature, reuse,
                            *rest.fetch_values(
                              :agriculture, :industry, :utilities, :transport
                            ) {|missing| nil }
                              
                          ),
                          street_address: [
                            !address_a.empty? ? address_a : nil,
                            !address_b.empty? ? address_b : nil,
                            !address_c.empty? ? address_c : nil
                          ].compact.join(SubFieldSeparator),
                          locality: locality,
                          region: '',
                          postcode: postcode.to_s.upcase,
                          country_name: '',
                          homepage: Types.normalise_url(website),
                          # blank sensitive data until new institutional email field added
                          #phone: normalise_phone_number(phone),
                          #email: email,
                          phone: '',
                          email: '',
                          twitter: normalise_twitter_handle(twitter),
                          facebook: Types.normalise_facebook([facebook, "http://fb.me/#{facebook}", website], base_url: ''),
                          qualifiers: '',
                          base_membership_type: '',
                          companies_house_number: '',
                          latitude: latitude,
                          longitude: longitude,
                          geocontainer: '',
                          geocontainer_lat: '',
                          geocontainer_lon: '',
                        }
          end
        end
                        
        # Entry point if invoked as a script.
        #
        # Expects a {SeOpenData::Config} object as the parameter, to
        # define the locations of various resources, and set options on
        # the conversion process.
        #
        # Configurations specific to this method
        # ORIGINAL_CSV_COL_SEP - sets the original CSV's column separator (default ';')
        def self.convert(config)

          # original src csv file
          original_csv = File.join(config.SRC_CSV_DIR, config.ORIGINAL_CSV)

          # Intermediate csv files
          initial_pass = File.join(config.GEN_CSV_DIR, "initiatives.csv")

          # Output csv file
          output_csv = config.STANDARD_CSV

          # Get the Geoapify API key
          pass = SeOpenData::Utils::PasswordStore.new(use_env_vars: config.USE_ENV_PASSWORDS)
          api_key = pass.get config.GEOCODER_API_KEY_PATH

          # Create a csv converter
          from_schema = SeOpenData::CSV::Schema.load_file(config.ORIGINAL_CSV_SCHEMA)
          to_schema = SeOpenData::CSV::Schemas::Latest;
          col_sep = config.fetch('ORIGINAL_CSV_COL_SEP', ';')
          converter = mk_converter(from_schema: from_schema, to_schema: to_schema,
                                   input_csv_opts: {col_sep: col_sep,
                                                    skip_blanks: true})
          
          # Transforms the rows from Co-ops UK schema to our standard
          # Note the BOM and encoding flags, which avoid a MalformedCSVError
          converter.convert File.open(original_csv, "r:bom|utf-8"), initial_pass
          add_postcode_lat_long(infile: initial_pass, outfile: output_csv,
                                api_key: api_key, lat_lng_cache: config.POSTCODE_LAT_LNG_CACHE,
                                postcode_global_cache: config.GEODATA_CACHE,
                                to_schema: to_schema)
        rescue => e
          raise "error transforming #{original_csv} into #{output_csv}: #{e.message}"
        end

        private


        def self.subhash(hash, *keys)
          keys = keys.select { |k| hash.key?(k) }
          Hash[keys.zip(hash.values_at(*keys))]
        end

        def self.normalise_phone_number(val)
          val
            .to_s
            .delete("() ")
            .sub(/^\+?44/, "0")
            .sub(/^00/, "0")
            .gsub(/[^\d]/, "")
        end

        def self.normalise_twitter_handle(val)
          val
            .downcase
            .sub(/h?t?t?p?s?:?\/?\/?w?w?w?\.?twitter\.com\//, "")
            .delete("@#/")
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
        # @param infile A file path to read from
        # @param outfile A file path to write to
        # @param api_key An API key to use for the global geocoder, optional if
        # postcode_global_cache not set
        # @param country_field_id The field id to use as the country component of the lookup
        # defaults to :country_name for historical backward compatibility.
        # @param lat_lng_cache The path to a JSON file into which to cache postcode geolocations
        # @param postcode_global_cache The path to JSON file into which to cache global
        # address geolocations
        # @param to_schema An SeOpenData::CSV::Schema instance defining the output schema
        # @param replace_address A boolean value, if true addresses in the CSV are replaced with
        # the resolved address from the geocoder. Defaults to false.
        def self.add_postcode_lat_long(infile:, outfile:, api_key:,
                                       country_field_id: :country_name,
                                       lat_lng_cache:, postcode_global_cache:,
                                       to_schema:, use_ordinance_survey: true,
                                       replace_address: false)
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
            {},
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


        
        # Given equal sized arrays of values and labels, create a concatenated list of labels
        #
        # For each value of `val_ary` which equals a value in
        # `true_vals`, include the corresponding label from
        # `label_ary` in the result.
        #
        # @param val_ary [Enumerable] An array of values, to interpret as booleans
        # @param label_ary [Enumerable] An array of labels, whose
        # sequence corresponds to `val_ary`
        # @param true_vals [Enumerable] Lists all the values which represent boolean truth.
        # Note: `val_ary` values are upper-cased before comparison with `true_vals`.
        # @param separator [String] A string to join the resulting labels with.
        # @return A string containing all the matching labels, joined by `separator`.
        def self.index_bools(val_ary, label_ary, true_vals: ["Y"], separator: SubFieldSeparator)
          zipped = val_ary.zip(label_ary)
          labels = zipped.collect do |val, label|
            !val.nil? && true_vals.include?(val.upcase) ? label : nil
          end
          return labels.compact.join(separator)
        end
        
        # Map a LimeSurvey response ID to the equivalent activity label
        #
        # @param activity [String] the LimeSurvey "primary activity"
        # question's response ID. May be null.
        #
        # @return a prefLabel taken from the file
        # `essglobal/standard/activities-modified.skos` in the
        # `map-sse` project, or the empty string if no match found
        def self.primary_activity_label(activity)
          ix = @activities_modified.find_index do |a|
            activity == a[:activity_id]
          end
          return '' if ix.nil?
          label = @activities_modified[ix].fetch(:label, '')
          return label
        end


        # Map a set of LimeSurvey yes/no values to a concatenated list
        # of labels with affirmative values.
        #
        # Each item in the list is a prefLabel taken from the file
        # `essglobal/standard/organisational-structure.skos` in the
        # `map-sse` project.
        #
        # @return a list of strings, separated by {SubFieldSeparator}.
        def self.organisational_structure_label(
              community_group, non_profit, social_enterprise, charity,
              company, workers_coop, housing_coop, consumer_coop,
              producer_coop, stakeholder_coop,
              community_interest_company, community_benefit_society
            )
          return index_bools(
                   [community_group,
                    non_profit,
                    social_enterprise,
                    charity,
                    company,
                    workers_coop,
                    housing_coop,
                    consumer_coop,
                    producer_coop,
                    stakeholder_coop,
                    nil, # secondary coop
                    nil, # coop
                    community_interest_company,
                    community_benefit_society,
                   ],
                   @organisational_structure.collect {|a| a[:label] })
        end        

        # Map a set of LimeSurvey yes/no values to a concatenated list
        # of labels with affirmative values.
        #
        # Each item in the list is a prefLabel taken from the file
        # `essglobal/standard/activities-modified.skos` in the
        # `map-sse` project.
        #
        # @return a list of strings, separated by {SubFieldSeparator}.
        def self.secondary_activity_labels(arts, campaigning, community,
                                           education, energy, food, goods_services,
                                           health, housing, money, nature, reuse,
                                           agriculture, industry, utilities, transport)
          return index_bools([arts, campaigning, community,
                              education, energy, food, goods_services,
                              health, housing, money, nature, reuse,
                              agriculture, industry, utilities, transport],
                             @activities_modified.collect {|a| a[:label]})
        end
        

        # The following are essentially a bit of built-in schema. This
        # is bad! All the defs should be in the schema definitions
        # elsewhere. However, we're not that sophisticated yet.
        
        # This table maps the term IDs in
        # `map-sse:vocabs/standard/activities-modified.skos` To a)
        # their labels, and b) the IDs used in the LimeSurvey
        # questions "activity" and "secondary activity". The order
        # matters, it should be in order of ID.
        @activities_modified = [
          {id: :AM10,
           label: 'Arts, Media, Culture & Leisure',
           activity_id: 'SQ001',
           secondary_activity_id: 'SQ002'},
          {id: :AM20,
           label: 'Campaigning, Activism & Advocacy',
           activity_id: 'SQ002',
           secondary_activity_id: 'SQ003'},
          {id: :AM30,
           label: 'Community & Collective Spaces',
           activity_id: 'SQ003',
           secondary_activity_id: 'SQ004'},
          {id: :AM40,
           label: 'Education',
           activity_id: 'SQ004',
           secondary_activity_id: 'SQ005'},
          {id: :AM50,
           label: 'Energy',
           activity_id: 'SQ005',
           secondary_activity_id: 'SQ006'},
          {id: :AM60,
           label: 'Food',
           activity_id: 'SQ006',
           secondary_activity_id: 'SQ007'},
          {id: :AM70,
           label: 'Goods & Services',
           activity_id: 'SQ007',
           secondary_activity_id: 'SQ008'},
          {id: :AM80,
           label: 'Health, Social Care & Wellbeing',
           activity_id: 'SQ008',
           secondary_activity_id: 'SQ009'},
          {id: :AM90,
           label: 'Housing',
           activity_id: 'SQ009',
           secondary_activity_id: 'SQ010'},
          {id: :AM100,
           label: 'Money & Finance',
           activity_id: 'SQ010',
           secondary_activity_id: 'SQ011'},
          {id: :AM110,
           label: 'Nature, Conservation & Environment',
           activity_id: 'SQ011',
           secondary_activity_id: 'SQ012'},
          {id: :AM120,
           label: 'Reduce, Reuse, Repair & Recycle',
           activity_id: 'SQ012',
           secondary_activity_id: 'SQ013'},
          {id: :AM130,
           label: 'Agriculture',
           activity_id: 'SQ013',
           secondary_activity_id: 'SQ014'},
          {id: :AM140,
           label: 'Industry',
           activity_id: 'SQ014',
           secondary_activity_id: 'SQ015'},
          {id: :AM150,
           label: 'Utilities',
           activity_id: 'SQ015',
           secondary_activity_id: 'SQ016'},
          {id: :AM160,
           label: 'Transport',
           activity_id: 'SQ016',
           secondary_activity_id: 'SQ017'},
        ]

        # This table maps the term IDs in
        # `map-sse:vocabs/standard/organisational-structure.skos` To
        # a) their labels, and b) the IDs used in the LimeSurvey
        # questions "structure".  The order matters, it should be in
        # order of ID.
        @organisational_structure = [
          {id: :OS10,
           label: 'Community group (formal or informal)',
           structure_id: 'SQ001'},
          {id: :OS20,
           label: 'Not-for-profit organisation',
           structure_id: 'SQ002'},
          {id: :OS30,
           label: 'Social enterprise',
           structure_id: 'SQ003'},
          {id: :OS40,
           label: 'Charity',
           structure_id: 'SQ004'},
          {id: :OS50,
           label: 'Company (Other)',
           structure_id: 'SQ005'},
          {id: :OS60,
           label: 'Workers co-operative',
           structure_id: 'SQ006'},
          {id: :OS70,
           label: 'Housing co-operative',
           structure_id: 'SQ007'},
          {id: :OS80,
           label: 'Consumer co-operative',
           structure_id: 'SQ008'},
          {id: :OS90,
           label: 'Producer co-operative',
           structure_id: 'SQ009'},
          {id: :OS100,
           label: 'Multi-stakeholder co-operative',
           structure_id: 'SQ010'},
          {id: :OS110,
           label: 'Secondary co-operative',
           structure_id: nil},
          {id: :OS115,
           label: 'Co-operative',
           structure_id: nil},
          {id: :OS120,
           label: 'Community Interest Company (CIC)',
           structure_id: 'SQ011'},
          {id: :OS130,
           label: 'Community Benefit Society / Industrial and Provident Society (IPS)',
           structure_id: 'SQ012'},
          {id: :OS140,
           label: 'Employee trust',
           structure_id: nil},
          {id: :OS150,
           label: 'Self-employed',
           structure_id: nil},
          {id: :OS160,
           label: 'Unincorporated',
           structure_id: nil},
          {id: :OS170,
           label: 'Mutual',
           structure_id: nil},
          {id: :OS180,
           label: 'National apex',
           structure_id: nil},
          {id: :OS190,
           label: 'National sectoral federation or union',
           structure_id: nil},
          {id: :OS200,
           label: 'Regional, state or provincial level federation or union',
           structure_id: nil},
          {id: :OS210,
           label: 'Cooperative group',
           structure_id: nil},
          {id: :OS220,
           label: 'Government agency/body',
           structure_id: nil},
          {id: :OS230,
           label: 'Supranational',
           structure_id: nil},
          {id: :OS240,
           label: 'Cooperative of cooperatives / mutuals',
           structure_id: nil},
        ]

      end
    end
  end
end
