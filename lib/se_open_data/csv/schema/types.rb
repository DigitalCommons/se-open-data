require 'csv'
require 'se_open_data/utils/log_factory'
require 'i18n'

I18n.available_locales = [:en]

module SeOpenData
  module CSV
    class Schema
      class Types
        # Create a log instance
        Log = SeOpenData::Utils::LogFactory.default

        def self.normalise_email(val, default: '', throw: false)
          if val.to_s =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
            val
          else
            if throw
              raise ArgumentError, "malformed email: '#{val}'"
            else
              Log.info("This doesn't look like an email: '#{val}'")
              default
            end
          end
        end
        
        def self.normalise_url(str, default: '', full_url: false, throw: false)
          val = str.to_s.strip.downcase

          match = val.match(%r{^(https?):/+(.*)}) # remove any URL scheme for now
          if match
            scheme, rest = match.values_at(1, 2)
          else 
            scheme = 'http' # default scheme
            rest = val
          end
          
          # Match two or more dotted names, optional port, optional
          # path, optional trailing slash.  If full_url is truthy,
          # match all of the URL to the end (defaut is false, for
          # backward-compatibility, but recommended value is true)
          pattern = full_url ? %r{^([\w-]+\.)+([\w-]+)(:\d+)?(/\S+)*/?$}
                    : %r{^([\w-]+\.)+([\w-]+)(:\d+)?(/\S+)*/?}
          
          rest.match(pattern) do |m|
            nrest = m[0].gsub(%r{/+}, '/')
            return "#{scheme}://#{nrest}"
          end

          if throw
            raise ArgumentError, "This doesn't look like a website: '#{str}'"
          else
            Log.info("This doesn't look like a website: '#{str}'")
            return default
          end
        end

        def self.normalise_facebook(items, base_url: 'https://www.facebook.com/', throw: false)
          return nil unless items
          items = [items] unless items.respond_to? :each

          items.each do |str|
            Log.debug "Attempting to normalise Facebook URL: '#{str}'"
            url = normalise_url(str.to_s, default: nil, full_url: true, throw: throw)
            if url.nil?
              Log.info "Ignoring un-normalisable URL: '#{str}'"
              next
            end
            
            # remove any query or anchor portion
            url.sub!(/[?#].*/, '');

            # remove any trailing slash delimiters
            url.sub!(%r{/+$}, '')
            
            # Note, we don't match *just* the facebook url with no path. i.e.
            # Just 'https://www.facebook.com/' alone is not a valid facebook URL
            url.downcase.match(%r{^https?://([\w-]+\.)?facebook.com/(.+)}) do |m|
              return base_url+m[2]
            end
            url.downcase.match(%r{^https?://([\w-]+\.)?fb.me/(.+)}) do |m|
              return base_url+m[2]
            end

            if throw
              raise ArgumentError, "non-Facebook URL: '#{str}'"
            end
            
            Log.info "Ignoring non-facebook URL: '#{str}'"
          end
          
          return nil
        end

        def self.normalise_twitter(items, base_url: 'https://twitter.com/', throw: false)
          return nil unless items
          items = [items] unless items.respond_to? :each

          items.each do |str|
            Log.debug "Attempting to normalise Twitter URL: '#{str}'"
            url = normalise_url(str.to_s, default: nil, full_url: true, throw: throw)
            if url.nil?
              Log.info "Ignoring un-normalisable URL: '#{str}'"
              next
            end
            
            # remove any query or anchor portion
            url.sub!(/[?#].*/, '');

            # remove any trailing slash delimiters
            url.sub!(%r{/+$}, '')
            
            # Note, we don't match *just* the twitter url with no path. i.e.
            # Just 'https://www.twitter.com/' alone is not a valid twitter URL
            url.downcase.match(%r{^https?://([\w-]+\.)?twitter.com/(.+)}) do |m|
              return base_url+m[2]
            end
            
            if throw
              raise ArgumentError, "non-twitter URL: '#{str}'"
            end
            
            Log.info "Ignoring non-twitter URL: '#{str}'"
          end
          return nil
        end

        def self.normalise_float(val, default: 0, throw: false)
          if val =~ /^[+-]?\d+[.]\d+$/
            val
          else
            if throw
              raise ArgumentError, "this doesn't look lik a float: '#{val}'"
            else
              default
            end
          end
        end

        # given a list of address parts via the parameters, try to
        # clean it the parts, removing extra commas, strange
        # punctuation etc.  and return a concatenated version
        # delimited by commas.
        def self.normalise_addr(*parts)
          parts.compact
            .map {|it| it.strip.gsub(/[;,](\s*[;,])+/, ',').gsub(/[\s,;]*$/, '') }
            .select {|it| it != '' }
            .join(", ")
        end

        # Searches an international vocab for a description, returns the term
        # The search can optionally be limited to a language
        def self.identify_vocab(text, i18n_vocab, lang: nil)
          target = to_sym(text)
          lang = lang.to_s.downcase
          i18n_vocab.each do |code, vocab|
            next if lang && lang != code.to_s.downcase
            raise "can't find vocab terms element" unless terms = vocab["terms"]
            
            terms.each do |term, descr|
              return term if target == to_sym(descr)
            end
          end
          return
        end
        
        # converts a string to a valid ruby symbolic identifier
        def self.to_sym(str)
          parameterize(str.to_s.strip.downcase.tr('-','_'), separator: "_").to_sym
        end
        
        # Splits the field by the given delimiter, passes to the block for mapping,
        #
        # Parses the block like a CSV row, with default delimiter
        # character ';' and quote character "'" (needed for values
        # with the delimiter within). The escape character is '\\'
        #
        # @param val [String] the multi-value field
        # @param delim [String] the sub-field delimiter character to parse
        # @param outdelim [String] the sub-field delimiter character to output
        # @param quote [String] the sub-field quote character to parse
        # @param outquote [String] the sub-field quote character to output
        def self.multivalue(val, delim: ';', quote: "'", outdelim: ';', outquote: "'")
          subfields = multivalue_split(vals, quote: quote, delim: delim)
          new_subfields = subfields.collect {|field| yield field.strip, subfields }.compact
          ::CSV.generate_line(new_subfields,
                              quote_char: outquote, col_sep: outdelim).chomp
        end

        # Joins an array of un-escaped sub-field values by the given delimiter
        #
        # @param val [String] the sub-fields
        # @param outdelim [String] the sub-field delimiter character
        # @param outquote [String] the sub-field quote character
        def self.multivalue_join(vals, outquote: "'", outdelim: ';')
          ::CSV.generate_line(vals,
                              quote_char: outquote, col_sep: outdelim).chomp
        end

        # Splits a multivalue field value by the given delimiter
        #
        # @returns an array of the unescaped values
        #
        # @param val [String] the multi-value field
        # @param delim [String] the sub-field delimiter character to parse
        # @param quote [String] the sub-field quote character to parse
        def self.multivalue_split(vals, delim: ';', quote: "'")
          ::CSV.parse_line(vals.to_s, quote_char: quote, col_sep: delim).to_a
        end

        # Converts a two-letter country code to a country name.
        #
        # @code [#to_s] the code to convert
        # @return [String|nil] the country name in English,  or nil, if no match was found.
        def self.country_code_to_name(code)
          @@country_codes[:"#{code.to_s.upcase}"]
        end

        # Turn a string into a parameter name
        #
        # Borrowed from the Rails codebase
        def self.parameterize(string, separator: "-", preserve_case: false)
          # Replace accented chars with their ASCII equivalents.
          parameterized_string = I18n.transliterate(string)

          # Turn unwanted chars into the separator.
          parameterized_string.gsub!(/[^a-z0-9\-_]+/, separator)

          unless separator.nil? || separator.empty?
            if separator == "-".freeze
              re_duplicate_separator        = /-{2,}/
              re_leading_trailing_separator = /^-|-$/
            else
              re_sep = Regexp.escape(separator)
              re_duplicate_separator        = /#{re_sep}{2,}/
              re_leading_trailing_separator = /^#{re_sep}|#{re_sep}$/
            end
            # No more than one of the separator in a row.
            parameterized_string.gsub!(re_duplicate_separator, separator)
            # Remove leading/trailing separator.
            parameterized_string.gsub!(re_leading_trailing_separator, "".freeze)
          end

          parameterized_string.downcase! unless preserve_case
          parameterized_string
        end
        
        @@country_codes = {
          AF: "Afghanistan",
          AX: "Aland Islands",
          AL: "Albania",
          DZ: "Algeria",
          AS: "American Samoa",
          AD: "Andorra",
          AO: "Angola",
          AI: "Anguilla",
          AQ: "Antarctica",
          AG: "Antigua And Barbuda",
          AR: "Argentina",
          AM: "Armenia",
          AW: "Aruba",
          AU: "Australia",
          AT: "Austria",
          AZ: "Azerbaijan",
          BS: "Bahamas",
          BH: "Bahrain",
          BD: "Bangladesh",
          BB: "Barbados",
          BY: "Belarus",
          BE: "Belgium",
          BZ: "Belize",
          BJ: "Benin",
          BM: "Bermuda",
          BT: "Bhutan",
          BO: "Bolivia",
          BA: "Bosnia And Herzegovina",
          BW: "Botswana",
          BV: "Bouvet Island",
          BR: "Brazil",
          IO: "British Indian Ocean Territory",
          BN: "Brunei Darussalam",
          BG: "Bulgaria",
          BF: "Burkina Faso",
          BI: "Burundi",
          KH: "Cambodia",
          CM: "Cameroon",
          CA: "Canada",
          CV: "Cape Verde",
          KY: "Cayman Islands",
          CF: "Central African Republic",
          TD: "Chad",
          CL: "Chile",
          CN: "China",
          CX: "Christmas Island",
          CC: "Cocos (Keeling) Islands",
          CO: "Colombia",
          KM: "Comoros",
          CG: "Congo",
          CD: "Congo, Democratic Republic",
          CK: "Cook Islands",
          CR: "Costa Rica",
          CI: "Cote D'Ivoire",
          HR: "Croatia",
          CU: "Cuba",
          CY: "Cyprus",
          CZ: "Czech Republic",
          DK: "Denmark",
          DJ: "Djibouti",
          DM: "Dominica",
          DO: "Dominican Republic",
          EC: "Ecuador",
          EG: "Egypt",
          SV: "El Salvador",
          GQ: "Equatorial Guinea",
          ER: "Eritrea",
          EE: "Estonia",
          ET: "Ethiopia",
          FK: "Falkland Islands (Malvinas)",
          FO: "Faroe Islands",
          FJ: "Fiji",
          FI: "Finland",
          FR: "France",
          GF: "French Guiana",
          PF: "French Polynesia",
          TF: "French Southern Territories",
          GA: "Gabon",
          GM: "Gambia",
          GE: "Georgia",
          DE: "Germany",
          GH: "Ghana",
          GI: "Gibraltar",
          GR: "Greece",
          GL: "Greenland",
          GD: "Grenada",
          GP: "Guadeloupe",
          GU: "Guam",
          GT: "Guatemala",
          GG: "Guernsey",
          GN: "Guinea",
          GW: "Guinea-Bissau",
          GY: "Guyana",
          HT: "Haiti",
          HM: "Heard Island & Mcdonald Islands",
          VA: "Holy See (Vatican City State)",
          HN: "Honduras",
          HK: "Hong Kong",
          HU: "Hungary",
          IS: "Iceland",
          IN: "India",
          ID: "Indonesia",
          IR: "Iran, Islamic Republic Of",
          IQ: "Iraq",
          IE: "Ireland",
          IM: "Isle Of Man",
          IL: "Israel",
          IT: "Italy",
          JM: "Jamaica",
          JP: "Japan",
          JE: "Jersey",
          JO: "Jordan",
          KZ: "Kazakhstan",
          KE: "Kenya",
          KI: "Kiribati",
          KR: "Korea",
          KW: "Kuwait",
          KG: "Kyrgyzstan",
          LA: "Lao People's Democratic Republic",
          LV: "Latvia",
          LB: "Lebanon",
          LS: "Lesotho",
          LR: "Liberia",
          LY: "Libyan Arab Jamahiriya",
          LI: "Liechtenstein",
          LT: "Lithuania",
          LU: "Luxembourg",
          MO: "Macao",
          MK: "Macedonia",
          MG: "Madagascar",
          MW: "Malawi",
          MY: "Malaysia",
          MV: "Maldives",
          ML: "Mali",
          MT: "Malta",
          MH: "Marshall Islands",
          MQ: "Martinique",
          MR: "Mauritania",
          MU: "Mauritius",
          YT: "Mayotte",
          MX: "Mexico",
          FM: "Micronesia, Federated States Of",
          MD: "Moldova",
          MC: "Monaco",
          MN: "Mongolia",
          ME: "Montenegro",
          MS: "Montserrat",
          MA: "Morocco",
          MZ: "Mozambique",
          MM: "Myanmar",
          NA: "Namibia",
          NR: "Nauru",
          NP: "Nepal",
          NL: "Netherlands",
          AN: "Netherlands Antilles",
          NC: "New Caledonia",
          NZ: "New Zealand",
          NI: "Nicaragua",
          NE: "Niger",
          NG: "Nigeria",
          NU: "Niue",
          NF: "Norfolk Island",
          MP: "Northern Mariana Islands",
          NO: "Norway",
          OM: "Oman",
          PK: "Pakistan",
          PW: "Palau",
          PS: "Palestinian Territory, Occupied",
          PA: "Panama",
          PG: "Papua New Guinea",
          PY: "Paraguay",
          PE: "Peru",
          PH: "Philippines",
          PN: "Pitcairn",
          PL: "Poland",
          PT: "Portugal",
          PR: "Puerto Rico",
          QA: "Qatar",
          RE: "Reunion",
          RO: "Romania",
          RU: "Russian Federation",
          RW: "Rwanda",
          BL: "Saint Barthelemy",
          SH: "Saint Helena",
          KN: "Saint Kitts And Nevis",
          LC: "Saint Lucia",
          MF: "Saint Martin",
          PM: "Saint Pierre And Miquelon",
          VC: "Saint Vincent And Grenadines",
          WS: "Samoa",
          SM: "San Marino",
          ST: "Sao Tome And Principe",
          SA: "Saudi Arabia",
          SN: "Senegal",
          RS: "Serbia",
          SC: "Seychelles",
          SL: "Sierra Leone",
          SG: "Singapore",
          SK: "Slovakia",
          SI: "Slovenia",
          SB: "Solomon Islands",
          SO: "Somalia",
          ZA: "South Africa",
          GS: "South Georgia And Sandwich Isl.",
          ES: "Spain",
          LK: "Sri Lanka",
          SD: "Sudan",
          SR: "Suriname",
          SJ: "Svalbard And Jan Mayen",
          SZ: "Swaziland",
          SE: "Sweden",
          CH: "Switzerland",
          SY: "Syrian Arab Republic",
          TW: "Taiwan",
          TJ: "Tajikistan",
          TZ: "Tanzania",
          TH: "Thailand",
          TL: "Timor-Leste",
          TG: "Togo",
          TK: "Tokelau",
          TO: "Tonga",
          TT: "Trinidad And Tobago",
          TN: "Tunisia",
          TR: "Turkey",
          TM: "Turkmenistan",
          TC: "Turks And Caicos Islands",
          TV: "Tuvalu",
          UG: "Uganda",
          UA: "Ukraine",
          AE: "United Arab Emirates",
          GB: "United Kingdom",
          US: "United States",
          UM: "United States Outlying Islands",
          UY: "Uruguay",
          UZ: "Uzbekistan",
          VU: "Vanuatu",
          VE: "Venezuela",
          VN: "Viet Nam",
          VG: "Virgin Islands, British",
          VI: "Virgin Islands, U.S.",
          WF: "Wallis And Futuna",
          EH: "Western Sahara",
          YE: "Yemen",
          ZM: "Zambia",
          ZW: "Zimbabwe"
        }
      end
    end
  end
end
