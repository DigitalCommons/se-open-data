require 'se_open_data/csv/row_reader'
require 'se_open_data/initiative'
require 'se_open_data/utils/progress_counter'
require 'se_open_data/utils/log_factory'

module SeOpenData
  class Initiative
    class Collection < Array
      # Create a log instance
      Log = SeOpenData::Utils::LogFactory.default
      
      # These files define other methods of this class
      require 'se_open_data/initiative/collection/rdf'
      require 'se_open_data/initiative/collection/html'
      require 'se_open_data/initiative/collection/sparql'
      
      IndexBasename = "index"
      attr_reader :config
      def initialize(config)
        @config = config
        @graph = nil    # Huh? What's this for?
        super()
      end
      def html
        @html ||= HTML::new(self, config)
      end
      def rdf
        @rdf ||= RDF::new(self, config)
      end
      def sparql
        @sparql ||= Sparql::new(self, config)
      end
      def add_from_csv(input_io, csv_opts = {})
        # The way this works is based on having column headings:
        csv_opts.merge!(headers: true)
        csv_in = ::CSV.new(input_io, **csv_opts)
        csv_in.each {|row|
          push Initiative.new(config, CSV::RowReader.new(row, @config.csv_standard::Headers))
        }
        self
      end
      def serialize_everything(outdir)
        # Save sparql query first, it's small and quick
        Log.debug "Creating SPARQL query"
        sparql.save_map_app_sparql_query
        # Create RDF for each initiative
        counter = SeOpenData::Utils::ProgressCounter.new("Saving RDF files for each initiative", size)
        each {|initiative|
          Log.debug "Serialising initiative #{initiative.id} as .rdf"
          initiative.rdf.save_rdfxml(outdir)
          Log.debug "Serialising initiative #{initiative.id} as .ttl"
          initiative.rdf.save_turtle(outdir)
          Log.debug "Serialising initiative #{initiative.id} as .html"
          initiative.html.save(outdir)
          counter.step
        }
        Log.debug "Serialising initiative index as .rdf"
        rdf.save_index_rdfxml(outdir)
        Log.debug "Serialising initiative index as .ttl"
        rdf.save_index_turtle(outdir)
        #Log.debug "Serialising all initiatives as .rdf"
        #rdf.save_one_big_rdfxml

        # Save the one-biggies last as they are slow, and do them in least order of likely to fail
        Log.debug "Serialising all initiatives as .n3.gz"
        rdf.save_one_big_ntriples
        #Log.debug "Serialising all initiatives as .ttl"
        #rdf.save_one_big_turtle
        Log.debug "Serialising all initiatives as .html"
        html.save(outdir)
      end
      def index_filename(outdir, ext)
        outdir + IndexBasename + ext
      end
      def one_big_filename(pathname_without_ext, ext)
        pathname_without_ext + ext
      end
    end
  end
end

