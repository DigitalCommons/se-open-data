require "linkeddata"
require "csv"
require "rdf"
require "se_open_data/essglobal/standard"

module SeOpenData
  class Initiative
    class RDF
      class Config
        Ospostcode = ::RDF::Vocabulary.new("http://data.ordnancesurvey.co.uk/id/postcodeunit/")
        Osspatialrelations = ::RDF::Vocabulary.new("http://data.ordnancesurvey.co.uk/ontology/spatialrelations/")
        Geo = ::RDF::Vocabulary.new("http://www.w3.org/2003/01/geo/wgs84_pos#")
        Rov = ::RDF::Vocabulary.new("http://www.w3.org/ns/regorg#")
        attr_reader :uri_prefix, :essglobal_uri, :essglobal_vocab, :one_big_file_basename, :map_app_sparql_query_filename, :css_files, :essglobal_standard, :postcodeunit_cache, :organisational_structure_lookup, :activities_mod_lookup, :qualifiers_lookup, :base_membership_type_lookup, :countries_lookup, :territories_lookup, :activities_lookup, :csv_standard, :sameas

        # Constructor
        #
        # @param output_directory [String] - directory where RDF serializations are to be created
        # @param uri_prefix [String] - a string which prefixes every initiative's URI
        # @param essglobal_uri [String] - base URI for the essglobal vocabulary. e.g. http://purl.org/essglobal
        # @param one_big_file_basename [String] - filename (except .extension) for files with all generated data concatenated for loading into Virtuoso
        # @param map_app_sparql_query_filename [String] - name of file where SPARQL query for sea-map app is to be written
        # css_files [Array<String>] - list of CSS files for linking from generated HTML
        # @param postcodeunit_cache [String] - JSON file where OS postcode unit results are cached
        # csv_standard [Class] - FIXME
        # @param sameas_csv [String] - name of CSV file with OWL sameAs relations. If defined, sameas_headers: must be defined too
        # @param sameas_headers [String] - CSV file where the equivalent URIs are stored
        def initialize(uri_prefix, essglobal_uri, one_big_file_basename, map_app_sparql_query_filename, css_files, postcodeunit_cache_filename, csv_standard, sameas_csv = nil, sameas_headers = nil, using_ica_activities = false)
          @uri_prefix = uri_prefix.sub(%r{/*$}, "/") # ensure trailing delim
          @essglobal_uri = essglobal_uri
          @essglobal_vocab = ::RDF::Vocabulary.new(essglobal_uri + "vocab/")
          @essglobal_standard = ::RDF::Vocabulary.new(essglobal_uri + "standard/")
          @one_big_file_basename = one_big_file_basename
          @map_app_sparql_query_filename = map_app_sparql_query_filename
          @css_files = css_files

          # Lookups for standard vocabs:
          # second param is a string that matches one of the filenames (but without `.skos`) in:
          # https://github.com/essglobal-linked-open-data/map-sse/tree/develop/vocabs/standard
          @organisational_structure_lookup = SeOpenData::Essglobal::Standard.new(essglobal_uri, "organisational-structure")
          @qualifiers_lookup = SeOpenData::Essglobal::Standard.new(essglobal_uri, "qualifiers")
          @base_membership_type_lookup = SeOpenData::Essglobal::Standard.new(essglobal_uri, "base-membership-type")
          if using_ica_activities
            @activities_mod_lookup = SeOpenData::Essglobal::Standard.new(essglobal_uri, "activities-ica")
          else
            @activities_mod_lookup = SeOpenData::Essglobal::Standard.new(essglobal_uri, "activities-modified")
          end
          
          @countries_lookup = SeOpenData::Essglobal::Standard.new(essglobal_uri, "countries-iso")
          
          @territories_lookup = SeOpenData::Essglobal::Standard.new(essglobal_uri, "territories-ica")
          
          @csv_standard = csv_standard

          # keys are URIs in *this* dataset. values are arrays of URIs in other datasets.
          @sameas = Hash.new { |h, k| h[k] = [] }
          if sameas_csv
            puts sameas_headers
            raise("Expected 2 sameas_headers to be defined") unless sameas_headers && sameas_headers.size == 2
            ::CSV.foreach(sameas_csv, headers: true) do |row|
              @sameas[row[1]] << row[0]
              "" "temporary fix to
second row is where its coming from i.e. will write to the one on the left
              first one is dotcoop second one is cuk
              @sameas[row[sameas_headers[0]]] << row[sameas_headers[1]]
              " ""
            end
          end
        end

        def prefixes
          {
            rdf: ::RDF.to_uri.to_s,
            dc: ::RDF::Vocab::DC.to_uri.to_s,
            vcard: ::RDF::Vocab::VCARD.to_uri.to_s,
            geo: ::RDF::Vocab::GEO.to_uri.to_s,
            owl: ::RDF::Vocab::OWL.to_uri.to_s,
            essglobal: essglobal_vocab.to_uri.to_s,
            gr: ::RDF::Vocab::GR.to_uri.to_s,
            foaf: ::RDF::Vocab::FOAF.to_uri.to_s,
            ospostcode: Ospostcode.to_uri.to_s,
            rov: Rov.to_uri.to_s,
            osspatialrelations: Osspatialrelations.to_uri.to_s,
          }
        end

        def initiative_rdf_type
          essglobal_vocab["SSEInitiative"]
        end
      end
    end
  end
end
