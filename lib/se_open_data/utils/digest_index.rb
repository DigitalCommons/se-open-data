require 'base64'
require 'csv'
require 'digest'
require 'uri'
require 'se_open_data/utils/log_factory'

# This manipulates digest indexes and stored files thereof.
#
# A digest index is an ordered list of (key, digest) pairs. Both key
# and digest are URL-safe strings. The keys represent a unique name
# for something, and the digest represents the value named.
#
# They are useful for comparing the state of datasets and comparing
# their changes, and thereby performing actions such as notification
# of additions, changes and removals.
#
# Specifically: the original use is represent the state of a
# STANDARD_CSV file, allowing for more than one key field (although
# this currently doesn't occur), and to allow change notification to
# be sent to a Murmurations index.
#
# Keys are an url-component encoded concatenation of one or more
# string values, joined with a '%20' (encoded space).  This delimiter
# is used as it is also URL safe, but will not be confused with
# encoded spaces from within the string values, as these are encoded
# using a '+'.
#
# Digests are URL-safe base-64 encoded SHA256 digests of some
# arbitrary data.
#
# DigestIndex instances are serialised as tab-delimited text files
# (TSVs), with this leading header row: "Key\tDigest\n". Zero or more
# newline-delimited rows follow, and there may be a trailing newline.
#
# These rows are sorted by the key, and then by the digest. This is to
# ensure a deterministic serialisation given any particular data set:
# if the data is the same, the file will be the same.  The order that
# the datset happens to be presented will is not change this.
#
# Each row has two fields, delimited with a tab character. As the
# header indicates, the first field is the key, and the second the
# digest.
class SeOpenData::Utils::DigestIndex
  # A logger object
  Log = SeOpenData::Utils::LogFactory.default

  attr_reader :digest, :index, :header

  # Creates a new instance 
  def initialize()
    @digest = Digest::SHA256.new
    @index = []
    @header = "Key\tDigest\n"
  end

  # Clears the index
  def clear
    @index = []
    return self
  end

  # Loads a CSV file and adds the digested rows to this index.
  #
  # key_fields indicate which CSV fields should be interpreted as the
  # unique key (although this is not checked or enforced). The value
  # should be an array of one or more header names.
  #
  # Existing index values are not removed before insertion.
  # The index is sorted after insertion.
  #
  # If any csv_opts are given, they are passed to the CSV constructor.
  #
  # Returns the instance itself, to facilitate method chaining.
  def load_csv(csv_file, key_fields: , csv_opts: {})
    
    # Convert CSV into digest index
    ::CSV.foreach(csv_file, headers:true, **csv_opts) do |row|
      next if row.header_row?
      key = row.fields(*key_fields)
              .map{|it| URI.encode_www_form_component(it) }
              .join("%20") # encode_www_form_component won't insert this, it uses +

      # Provide for these digests being used in URLs; omit padding as lengths fixed
      digest = Base64.urlsafe_encode64(@digest.digest(row.to_csv), padding: false)
      @index << [key, digest]
    end

    # Ensure a deterministic order - so a hash digest of this file itself
    # indicates if there were any changes
    @index.sort!

    return self
  end

  # Loads a TSV from a file into this instances index.
  #
  # The file is given by the only parameter.
  #
  # The file is assumed to be a digest index serialised as a correctly
  # formatted set of tab-delimited values, as defined above.  But only
  # the header is checked, and only a warning is logged should it not
  # match.
  #
  # Existing index values are not removed before insertion.
  # The index is sorted after insertion.
  #
  # Returns the instance itself, to facilitate method chaining.
  def load(index_file)
    File.open(index_file, 'r') do |io|
      header = io.gets # skip header line
      Log.warn "Invalid header" unless header == @header
      io.each do |line|
        (key, digest) = line.chomp.split("\t", 2)
        @index << [key, digest]
      end
    end

    @index.sort!
    
    return self    
  end

  # Loads a TSV from a string
  #
  # The string is the only parameter.
  #
  # The string is assumed to be a digest index serialised as a
  # correctly formatted set of tab-delimited values, as defined above.
  # But only the header is checked, and only a warning is logged
  # should it not match.
  #
  # Existing index values are not removed before insertion.
  # The index is sorted after insertion.
  #
  # Returns the instance itself, to facilitate method chaining.
  def parse_str(index)
    header = nil
    index.scan(/.*?\n\r?|.*/) do |line| # emulate .gets
      unless header
        header = line
        Log.warn "Invalid header" unless header == @header
        next
      end
      
      (key, digest) = line.chomp.split("\t", 2)
      @index << [key, digest || ''] if key != nil
    end

    @index.sort!
    
    return self    
  end
  
  # Writes a digest index to a file
  #
  # The format is as defined above.
  #
  # The index is assumed already sorted, so not sorted beforehand.
  #
  # Returns the instance itself, to facilitate method chaining.
  def save(index_file)
    File.open(index_file, 'w') do |str|
      str << @header
      @index.each do |item|
        (key, digest) = *item
        str << "#{key}\t#{digest}\n"
      end
    end

    return self
  end

  # Mark zero or more keys as "invalidated"
  #
  # What this indicates is that the values' state are unknown, and so
  # they should be updated whatever any new state is.
  #
  # In practice this is done by setting the values to nil, which
  # appears in the serialisation as an empty field.
  #
  # Returns the instance itself, to facilitate method chaining.  
  def invalidate(*keys)
    @index.each_with_index do |item, ix|
      key = item[0]
      if keys.include? key
        @index[ix][1] = nil
      end
    end
    return self
  end

  # Iterate over the index values
  #
  # The block given to this method is passed the key and digest as
  # parameters.
  def each
    @index.each do |item|
      yield *item
    end
  end

  # Iterate over the index values, collecting the results
  #
  # The block given to this method is passed the key and digest as
  # parameters. The return values of the block is used to create a new
  # sequence which is returned by the method.
  #
  def collect
    @index.collect do |item|
      yield *item
    end
  end

  alias_method :map, :collect

  # Converts the index to a hash.
  #
  # The new hash has the index's keys as keys, and the digests as values.
  def to_h(h = {})
    each do |key, digest|
      h[key] = digest
    end
    return h
  end
  
  # Compare this instance with another
  #
  # Invokes the block given, or returns a new list of deltas, as
  # described by SeOpenData::Utils::DigestIndex.compare
  def compare(new_index, &block)
    self.class.compare(self, new_index, &block)
  end

  # Compare two indexes.
  #
  # If a block is given, it is invoked once for each key which appears
  # in either old_index or new_index. Three parameters are passed: the
  # key, the value from old_index, and the value from new_index (or
  # nil if the value in not present in either case).
  #
  # Otherwise, an array of these "deltas" is returned, i.e. an array
  # of three-value arrays, which represent the key, old and new values
  # as above.
  #
  # The typical use case is to perform some action for each changed
  # key - a new and an old value indicates a change, just a new value
  # a creation, and just an old value a deletion.
  #
  # Returns the instance itself, to facilitate method chaining.
  def self.compare(old_index, new_index)
    old_h = old_index.to_h
    new_h = new_index.to_h
    
    keys = old_h.merge(new_h).keys.sort

    if block_given?
      keys.each do |key|
        yield key, old_h[key], new_h[key]
      end
      return self
    else
      deltas = []
      keys.each do |key|
        deltas << [key, old_h[key], new_h[key]]
      end
      return deltas
    end
  end
end
