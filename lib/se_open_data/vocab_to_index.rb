require "se_open_data/utils/log_factory"
require "rdf/query"

module SeOpenData

  # A class to transform SKOS concept schemes into a datastructure
  # which can be used by Mykomap (if converted to a JSON file)
  #
  # The constructor accepts a graph, expected to be list of SKOS
  # concept schemes (vocabularies).
  #
  # The #aggregate method can then transform these into the desired
  # datastructure defined by the config parameter.
  #
  # Designed to be used in place of the the `get_vocabs.php` script in
  # Mykomap, when static JSON files are preferred.
  #
  class VocabToIndex
    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default

    attr :graph

    # Construct an instance which operates on the given data, which
    # should be an enumeration of RDF::Statement objects
    def initialize(statements)
      @graph = ::RDF::Graph.new << statements
    end

    # Get solution collection of of the concept schemes which exist in
    # the graph matching the given list of concept scheme uris
    def query_schemes(schemes)
      query = ::RDF::Query.new(
        **{
          :scheme => {
            ::RDF.type => ::RDF::Vocab::SKOS.ConceptScheme,
            ::RDF::Vocab::DC11.title => :title,
          },
        }
      )

      # Filter out only those listed in schemes
      query.execute(@graph).filter do |soln|
        schemes.has_key?(soln.scheme.value)
      end
    end

    # Get a solution collection indicating the concepts in the graph
    # from the given concept scheme.
    def query_concepts(scheme)
      query = ::RDF::Query.new(
        **{
          :concept => {
            ::RDF.type => ::RDF::Vocab::SKOS.Concept,
            ::RDF::Vocab::SKOS.inScheme => scheme,
            ::RDF::Vocab::SKOS.prefLabel => :label,
          },
        }
      )
      query.execute(@graph)
    end

    # Transform the data according to the config parameter.
    #
    # The form of `config` is a hash object including two (symbolic)
    # entries:
    # 
    # - `vocabularies:` A list of SKOS vocabulary (AKA concept schemes)
    #   to index, and
    # - `languages:` A list of language identifiers (as two-letter
    #   lower-case symbols) to obtain labels for.
    #
    # Then, each item in the `:vocabularies` array is used to create a
    # SPARQL query for the given endpoints, that retrieves the vocabulary
    # URIs and their `skos:prefLabel` properties in the languages defined
    # by `:languages`, where available.
    #
    # The resulting query data is then aggregated into an index of
    # vocabulary term (AKA concept) URIs and their labels in the
    # requested languages.
    #
    # For example:
    #
    #     {
    #       languages: [:en, :fr, ... ],
    #
    #       vocabularies: => [
    #         { uris: => {
    #             "https://dev.lod.coop/essglobal/2.1/standard/activities-ica/" => "aci",
    #             "https://dev.lod.coop/essglobal/2.1/standard/countries-iso/" => "coun",
    #             "https://dev.lod.coop/essglobal/2.1/standard/regions-ica/" => "reg",
    #             "https://dev.lod.coop/essglobal/2.1/standard/super-regions-ica/" => "sreg",
    #             "https://dev.lod.coop/essglobal/2.1/standard/organisational-structure/" => "os",
    #             "https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/" => "bmt",
    #              ...
    #           }
    #         }
    #         ...
    #       ],
    #     }
    #
    # Notice that there can be more than one `:vocabularies` entry,
    # and each endpoint has a set of vocabularies associated. This is
    # because each represents a dataset which *could* come from a
    # separate source.  This is somewhat historical, resulting from
    # wanting to allow multiple SPARQL endpoints.
    #
    # Notice also that each vocabulary URL, assumed to be a SKOS
    # vocabulary scheme, has an associated abbreviation. Currently these
    # MUST match the abbreviations hardwired in the Mykomap code. The example
    # above shows the requried prefixes at the time of writing. The URLs
    # themselves can be whatever required to match the data being queried.
    #
    # Later, the fields defined for initiatives will be configurable, and
    # then the prefixes will be too.
    #
    # The return value is another hash, defining:
    #
    # - `:prefixes` - a map of scheme uris to their prefixes, as defined by the config.
    # - `:vocabs` - a map of scheme prefixes to language IDs to localised term indexes
    #   with a localised title.
    #
    # Note that output language IDs are capitalised.
    #
    # A slimmed-down example of the data returned given the config
    # example above.
    #
    #     {
    #       prefixes: {
    #         "https://dev.lod.coop/essglobal/2.1/standard/organisational-structure/": "os",
    #         "https://dev.lod.coop/essglobal/2.1/standard/activities-ica/": "aci",
    #         "https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/": "bmt",
    #         "https://dev.lod.coop/essglobal/2.1/standard/countries-iso/": "coun",
    #         "https://dev.lod.coop/essglobal/2.1/standard/regions-ica/": "reg",
    #         "https://dev.lod.coop/essglobal/2.1/standard/super-regions-ica/": "sreg"
    #       },
    #       vocabs: {
    #         "bmt:": {
    #           EN: {
    #             title: "Typology",
    #             terms: {
    #               "bmt:BMT20": "Producers",
    #                #... other terms here ...
    #             },
    #             #... other languages here ...
    #           }
    #         },
    #         "os:": {
    #           EN: {
    #             title: "Structure Type",
    #             terms: {
    #               "os:OS115": "Co-operative",
    #               # ... other terms here ...
    #             },
    #             # ... other languages here ...
    #           }
    #         },
    #         "sreg:": {
    #           EN: {
    #             title: "Super Regions",
    #             terms: {
    #               "sreg:I-AP": "Asia+Pacific",
    #                # ... other terms here ...
    #             },
    #             # ... other languages here ...
    #           }
    #         },
    #         "reg:": {
    #           EN: {
    #             title: "Regions",
    #             terms: {
    #               "reg:I-AM-CE": "Central America",
    #                # ... other terms here ...
    #             },
    #             # ... other languages here ...
    #           }
    #         },
    #         "aci:": {
    #           EN: {
    #             title: "Economic Activities",
    #             terms: {
    #               "aci:ICA140": "Financial Services",
    #               # ... other terms here ...
    #             },
    #             # ... other languages here ...
    #           }
    #         }
    #       },
    #       meta: {
    #         vocab_srcs: [
    #           {
    #             "endpoint": "http://dev.data.solidarityeconomy.coop:8890/sparql",
    #             "uris": {
    #               "https://dev.lod.coop/essglobal/2.1/standard/organisational-structure/": "os",
    #               "https://dev.lod.coop/essglobal/2.1/standard/activities-ica/": "aci",
    #               "https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/": "bmt",
    #               "https://dev.lod.coop/essglobal/2.1/standard/countries-iso/": "coun",
    #               "https://dev.lod.coop/essglobal/2.1/standard/regions-ica/": "reg",
    #               "https://dev.lod.coop/essglobal/2.1/standard/super-regions-ica/": "sreg"
    #             }
    #           }
    #         ],
    #         languages: [
    #           EN:,
    #           # ... other languages here ...
    #         ],
    #         queries: [
    #            # ... SPARQL queries for each element of vocabs_srcs here ...
    #         ]
    #       }
    #     }
    #
    # Note that some or all vocabulary terms may be missing if they do not
    # have `prefLabels` with the required language. The data needs to be
    # provisioned with a full set to avoid this.
    #
    # When terms are present but the vocabulary `dc:title` is not
    # localised, the title falls back to the un-localised title, if
    # present (mainly because current data does not define localisations
    # for these).
    #
    # URIs in the resulting data are also abbreviated whenever possibly by
    # using the abbreviations defined in the `uris` section. So a term
    # with the URI:
    #
    #     https://dev.lod.coop/essglobal/2.1/standard/countries-iso/US
    #
    # Would be abbreviated to:
    #
    #     coun:US
    #
    # The prefixes and abbreviations for them are supplied with the term
    # data.
    def aggregate(config)
      vocab_srcs = config[:vocabularies] || {}
      languages = config[:languages] || []

      # A URI -> prefix index
      uri2prefix = {}

      # A prefix -> URI index
      prefix2uri = {}

      # Duplicate URI or prefixes
      duplicate_uris = []
      duplicate_prefixes = []
      
      vocab_srcs.each do |vocab_src|
        vocab_src[:uris].each do |uri, prefix|
          prefix = prefix.to_sym
          
          # Insert this mapping, checking for duplicates
          if uri2prefix.has_key?(uri) and uri2prefix[uri] != prefix
            duplicate_uris << uri
          else
            uri2prefix[uri] = prefix
          end

          if prefix2uri.has_key?(prefix) and prefix2uri[prefix] != uri
            duplicate_prefixes << prefix
          else
            prefix2uri[prefix] = uri
          end
        end
      end

      # Any duplicates? Raise an error
      unless duplicate_prefixes.empty? and duplicate_uris.empty?
        raise ArgumentError, "config for #aggregate must not contain duplicates of these prefixes/uris: "+
                            duplicate_prefixes.concat(duplicate_uris).join(', ')
      end

      vocabs = {}
      result = {
        prefixes: uri2prefix,
        meta: {
          vocab_srcs: vocab_srcs,
          languages: languages, # empty means "whatever ya got"
          queries: [],
        },
        vocabs: vocabs,
      };

      vocab_srcs.each do |vocab_src|
        vocab_src_uris = vocab_src[:uris] || {}

        # Get the scheme query, and transform it into a hash of
        # abbreviated scheme URIs -> languages -> titles.  We do this
        # here so we can iterate over schemes, then languages, in the
        # next loop.
        schemes = query_schemes(vocab_src_uris).reduce({}) do |schemes, soln|          
          uri = soln.scheme
          title = soln.title

          # Omit languages not in the configured list
          if languages.empty? || languages.include?(title.language)
            schemes[uri] ||= {}
            schemes[uri][title.language] = title.value
          end
          
          schemes
        end

        # Now iterate the schemes, languages, and build the result datastructre
        schemes.each do |scheme, langs|
          # There will be one iteration here for each scheme.
          # Query all concepts for this scheme, and re-use it for each language.
          concepts =  query_concepts(scheme) 
          abbrev_scheme = scheme.pname(prefixes: prefix2uri).to_sym #.sub(/:$/, '') # remove trailing colon

          # Iterate over each language for this scheme
          langs.each do |lang, title|
            lang_s = lang.upcase.to_sym

            # Filter out all solutions not for this language
            lang_concepts = concepts.each.select do |soln|
              soln.label.language == lang
            end

            lang_concepts.each do |soln| # incorporate this concept label
              label = soln.label
              #warn "#{title}@#{lang} -> #{soln.concept.value} #{label}" # DEBUG
              
              # Ensure terms field is an object, even if empty
              vocabs[abbrev_scheme] ||= {}
              localised_concepts = vocabs[abbrev_scheme][lang_s] ||= {}
              localised_concepts[:title] ||= title.to_s
              localised_terms = localised_concepts[:terms] ||= {}
              
              concept = soln.concept
              # FIXME check for overwriting data
              if concept # concept info
                abbrev_concept = concept.pname(prefixes: prefix2uri).to_sym
                localised_terms[abbrev_concept] = label.to_s
              end
            end
          end
        end
      end
      
      return result
    end    
  end
end
