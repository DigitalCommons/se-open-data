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
    # the graph matching the given list of concept scheme uris.
    # If no schemes given, query them all.
    def query_schemes(schemes = nil)
      query = ::RDF::Query.new(
        **{
          :scheme => {
            ::RDF.type => ::RDF::Vocab::SKOS.ConceptScheme,
            ::RDF::Vocab::DC11.title => :title,
          },
        }
      )
      
      # Filter out only those listed in schemes
      concepts = query.execute(@graph)
      if schemes == nil
        concepts
      else
        concepts.filter do |soln|
          schemes.has_key?(soln.scheme.value)
        end
      end
    end

    # Get a solution collection indicating the concepts in the graph
    # from the given concept scheme. If the scheme is null, get them all.
    def query_concepts(scheme = nil)
      query = if scheme == nil
                ::RDF::Query.new(
                  **{
                    :concept => {
                      ::RDF.type => ::RDF::Vocab::SKOS.Concept,
                      ::RDF::Vocab::SKOS.prefLabel => :label,
                    },
                  }
                )
              else
                ::RDF::Query.new(
                  **{
                    :concept => {
                      ::RDF.type => ::RDF::Vocab::SKOS.Concept,
                      ::RDF::Vocab::SKOS.inScheme => scheme,
                      ::RDF::Vocab::SKOS.prefLabel => :label,
                    },
                  }
                )
              end
      query.execute(@graph)
    end

    def all_languages()
      languages = {}
      query_schemes.each do |scheme|
        languages[scheme.title.language] = true if scheme.title.language
      end
      query_concepts.each do |concept|
        languages[concept.label.language] = true if concept.label.language
      end
      languages.keys
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
      
      if languages.length == 0
        languages = all_languages
      end
        
      languages = languages.map(&:upcase).map(&:to_sym)
      
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
        Log.debug("Getting vocab_src #{vocab_src}")
        vocab_src_uris = vocab_src[:uris] || {}

        # Get the scheme query, and transform it into a hash of
        # abbreviated scheme URIs -> languages -> titles.  We do this
        # here so we can iterate over schemes, then languages, in the
        # next loop.
        # Note: some schemes may have no title, and won't be captured here.
        schemes = query_schemes(vocab_src_uris).reduce({}) do |schemes, soln|          
          uri = soln.scheme
          title = soln.title

          # Omit languages not in the configured list when indexing.
          # Special case: a non-localised title matches all languages.
          # This is so we do not exclude cases which are non-localised.
          norm_lang = title&.language.to_s.upcase.to_sym
          if languages.empty? || title&.language == nil || languages.include?(norm_lang)
            schemes[uri] ||= {}
            schemes[uri][norm_lang] = title&.value.to_s
          end
          
          schemes
        end
        Log.debug("Got schemes: #{schemes.to_a}")
        
        # Now iterate the target languages, and build the result datastructre
        Log.debug("Got languages: #{languages}")
        languages.each do |lang|

          schemes.each do |scheme, scheme_langs|
            # There will be one iteration here for each scheme.
            # Query all concepts for this scheme, and re-use it for each language.
            concepts =  query_concepts(scheme) 
            abbrev_scheme = scheme.pname(prefixes: prefix2uri).to_sym #.sub(/:$/, '') # remove trailing colon
            vocab = vocabs[abbrev_scheme] ||= {}
            
            # Collect the languageless title and concepts as fallbacks
            nolang_title = scheme_langs[:''].to_s            
            nolang_terms = index_terms(concepts, nil, prefix2uri)
            
            # Collect the target language title and concepts
            lang_title = scheme_langs[lang].to_s
            norm_lang = lang.to_s.upcase.to_sym
            
            # Create vocab from this list of concepts, merged with the defaults
            # with no language.
            v = vocab[norm_lang.to_sym] = {
              title: (lang_title.empty? ? nolang_title : lang_title),
              terms: nolang_terms.merge(
                index_terms(concepts, norm_lang, prefix2uri)
              ),
            }
            Log.debug("Got vocab #{abbrev_scheme} '#{v[:title]}' in #{norm_lang} "+
                      "(#{v[:terms].keys.size} terms)}")
          end
        end
      end
      
      return result
    end

    # Helper to index a set of concepts as a hash of abbreviated URIs to concept values
    # (Any later duplicate keys will overwrite earlier ones)
    # Languages are assumed to all be the same, so ignored.
    def index_terms(concepts, lang, prefix2uri)
      lang = lang.to_s.upcase
      localised_terms = {}

      concepts.each do |soln| # incorporate this concept label       
        # FIXME warn about potentially overwriting data
        next unless soln.concept
        
        label = if soln.label.language.to_s.upcase == lang
                  soln.label
                else
                  nil
                end
          
        abbrev_concept = soln.concept.pname(prefixes: prefix2uri).to_sym

        # Sets the concept to '' if nothing better
        if localised_terms[abbrev_concept] == nil || localised_terms[abbrev_concept] == ''
          localised_terms[abbrev_concept] = label.to_s
        end
      end

      localised_terms
    end      
  end
end
