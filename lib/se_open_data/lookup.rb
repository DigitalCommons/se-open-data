module SeOpenData
  require "csv"
  require "se_open_data/utils/log_factory"
  
  # Used to look up translations of values to other values.
  #
  # Values can be loaded  from a CSV file
  class Lookup
    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default
    
    # Params:
    # dict - the look-up table
    # strict - whether to use default values
    # default - the default value to return if strict is false
    def initialize(dict = {}, default: nil, strict: false)
      @index = dict
      @default = default
      @strict = !!strict
    end

    # Look up a value
    #
    # The key will be normalised by any normalising key block set, then
    # whitespace stripped, before looking up.
    #
    # The result will also be normalised by any normalising val block set.
    def get(key)
      if key == nil || key == ''
        return @default
      end
      nkey = @norm_key.call(key.to_s).to_s.strip if @norm_key
      if @index.has_key? nkey
        return @index.fetch(nkey)
      else
        if @strict
          raise "no match for key '#{key}' (normalised: '#{nkey}'). #{@index.inspect}"
        else
          Log.warn "no match for key '#{key}' (normalised: '#{nkey}'), using #{@default.inspect}"
        end
        return @default
      end
      
    end

    # Set a key normalising block
    #
    # It should accept a single paramter, the value,
    # and return the tidied version (e.g. lower-cased).
    #
    # Whitespace will also be stripped afterwards.
    def key(&block)
      @norm_key = block
      self
    end

    # Set a value normalising block
    #
    # It should accept a single paramter, the value,
    # and return the tidied version (e.g. lower-cased).
    #
    # Unlike the key, no stripping is performed.
    def val(&block)
      @norm_val = block
      self
    end
    
    # Loads a CSV mapping file.
    #
    # A yield block can be used to transform the key and value entries.
    # The block receives key and val parameters, and
    # should return a new pair of values.
    #
    # Duplicate keys will raise an exception.
    #
    # The from: and to: named paramters can be used to name the columns
    # to map. These default to mapping the first field to the second field
    #
    # Returns the object itself, to allow chaining.
    def load_csv(file, from: 0, to: 1, &block)
      @index = {}
      ::CSV.foreach(file, headers: true) do |row|
        key = nkey = row[from]
        val = nval = row[to]
        if val != nil and val != ''
          nkey = @norm_key.call(key) if @norm_key
          nval = @norm_val.call(val) if @norm_val

          if @index[nkey]
            abort "Duplicate key in column #{from} of #{file}: #{key} (un-normalised: #{nkey})"
          end
          
          @index[nkey] = nval

          Log.debug "map: #{key} -> #{val}"
        else
          Log.debug "skip: #{key} -> #{val}"
        end
      end
      
      self
    end
    
    alias_method :[], :get
    
  end
end

