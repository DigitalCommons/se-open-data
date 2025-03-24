require 'linkeddata'
require "se_open_data/utils/log_factory"

module SeOpenData
  class Initiative
    class Collection < Array
      class RDF
        # Create a log instance
        Log = SeOpenData::Utils::LogFactory.default
        
	      # This class is needed bacause insert_graph is a protected method of ::RDF::Graph.
	      # No other reason.
	      class Graph < ::RDF::Graph
	        def insert_graph(g)
	          super.insert_graph(g)
	        end
	      end
	      attr_reader :collection, :config
	      def initialize(collection, config)
	        @collection, @config = collection, config
	      end
	      def save_index_ntriples(outdir)
	        f = collection.index_filename(outdir, ".nt")
	        Log.info "Saving #{f}..."
	        ::RDF::NTriples::Writer.open(f) {|writer|
	          writer << index_graph
	        }
	      end
	      def save_index_rdfxml(outdir)
	        f = collection.index_filename(outdir, ".rdf")
	        Log.info "Saving #{f}..."
	        ::RDF::RDFXML::Writer.open(f, standard_prefixes: true, prefixes: config.prefixes) {|writer|
	          writer << index_graph
	        }
	      end
	      def save_index_turtle(outdir)
	        f = collection.index_filename(outdir, ".ttl")
	        Log.info "Saving #{f}..."
	        ::RDF::Turtle::Writer.open(f, standard_prefixes: true, prefixes: config.prefixes) {|writer|
	          writer << index_graph
	        }
	      end
              # This gzips the output as ntriples are verbose, and can get large
              # But writing them is much faster than RDF/XML and TTL!
	      def save_one_big_ntriples
                require "zlib"
	        f = collection.one_big_filename(config.one_big_file_basename, ".nt.gz")
	        Log.info "Saving #{f}..."
                Zlib::GzipWriter.open(f) do |gz|
                  ::RDF::NTriples::Writer.new(gz) do |writer|
	            writer << one_big_graph
	          end
                end
	      end
	      def save_one_big_rdfxml
	        f = collection.one_big_filename(config.one_big_file_basename, ".rdf")
	        Log.info "Saving #{f}..."
	        ::RDF::RDFXML::Writer.open(f, standard_prefixes: true, prefixes: config.prefixes) {|writer|
	          writer << one_big_graph
	        }
	      end
	      def save_one_big_turtle
	        f = collection.one_big_filename(config.one_big_file_basename, ".ttl")
	        Log.info "Saving #{f}..."
	        ::RDF::Turtle::Writer.open(f, standard_prefixes: true, prefixes: config.prefixes) {|writer|
	          writer << one_big_graph
	        }
	      end
	      private
	      def index_graph
	        # We're going to cache the results of this method in the variable @index_graph.
	        if @size_when_index_graph_created
	          # Of course, it is also possible that the cache could be outdated with the sizes matching.
	          # But this should catch the most likely error:
	          raise "Using outdated cache" unless @size_when_index_graph_created == @collection.size
	        end
	        @size_when_index_graph_created = @collection.size
	        # Caching the result means that we don't have to recreate the index_graph for each of the different serializations.
	        @index_graph ||= make_index_graph
	      end
	      def make_index_graph
	        graph = ::RDF::Graph.new
	        collection.each {|i|	# each initiative in the collection
	          graph.insert([i.rdf.uri, ::RDF.type, config.initiative_rdf_type])
	        }
	        graph
	      end
	      def one_big_graph
	        # We're going to cache the results of this method in the variable @one_big_graph.
	        if @size_when_one_big_graph_created
	          # Of course, it is also possible that the cache could be outdated with the sizes matching.
	          # But this should catch the most likely error:
	          raise "Using outdated cache" unless @size_when_one_big_graph_created == @collection.size
	        end
	        @size_when_one_big_graph_created = @collection.size
	        # Caching the result means that we don't have to recreate the one_big_graph for each of the different serializations.
	        @one_big_graph ||= make_one_big_graph
	      end
	      def make_one_big_graph
	        # N.B. This is not ::RDF::Graph because we need to be able to use the protected method insert_graph:
	        graph = Graph.new
	        counter = SeOpenData::Utils::ProgressCounter.new("Creating one big graph", collection.size)
	        collection.each {|i|	# each initiative in the collection
	          graph.insert_graph(i.rdf.graph)
	          counter.step
	        }
	        graph
	      end
      end
    end
  end
end
