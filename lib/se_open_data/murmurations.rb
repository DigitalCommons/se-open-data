require "se_open_data/utils/log_factory"
require "json"
require "httparty"
require 'normalize_country'
require 'digest'

module SeOpenData
  class Murmurations
    # Create a log instance
    Log = SeOpenData::Utils::LogFactory.default
    Sha256 = Digest::SHA256.new
    
    def initialize(base_publish_url: , index_url:)
      @base_publish_url = base_publish_url
      @index_url = index_url
      @register_url = index_url + '/nodes' 
    end

    # Returns a response code string or a status string
    def status_check(node_id)
      status_url = @register_url + '/' + node_id.to_s
      
      response = HTTParty.get(status_url)
      unless response.code == 200
        reason = "status check failed with response code #{response.code}"
        Log.warn "Profile #{node_id}: #{reason}"
        Log.debug response.body
        return response.code
      end

      content = response.parsed_response
      
      return content.dig('data', 'status')
    end
    
    def remove(node_id)
      delete_url = File.join(@index_url, node_id)
      response = HTTParty.delete(delete_url)
      unless response.code == 200
        reason = "deletion failed with status #{response.code}"
        Log.warn "Profile #{node_id}: #{reason}"
        Log.debug response.body
        return false
      end

      status = status_check(node_id)
      if status != 'deleted'
        reason = "deletion failed, status was '#{status}' not 'deleted'"
        Log.warn "Profile #{node_id}: #{reason}"
        Log.debug response.body
        return false
      end

      Log.info "Deleted profile #{node_id}"
      return true
    end

    def update(url)
      response = HTTParty.post(@register_url, body: { profile_url: url }.to_json)
      unless response.code == 200
        reason = "registration failed with status #{response.code}"
        Log.warn "Profile #{url}: #{reason}"
        Log.debug response.body
        return false
      end
      
      node_id = response.parsed_response.dig('data', 'node_id')
      unless node_id
        reason = "registration gave no node id"
        Log.warn "Profile #{url}: #{reason}"
        Log.debug response.body
        return false
      end

      status = status_check(node_id)
      unless %w(posted received validated).include? status
        reason = "status check failed with status/data #{status}"
        Log.warn "Profile #{url}: #{reason}"
        Log.debug response.body
        return false
      end
        
      Log.info "Registered #{url}"
      return true
    end
    
    # Register Murmurations profiles
    #
    # base_publish_url: Prepended to profile filenames to get their published URLs
    # index_url: the murmurations index server's base URL, assumed to be V2 of the API
    # update_urls: an array of profile urls to update (defaults to empty list)
    # remove_urls: an array of profile urls to remove (defaults to empty list)
    # delay: seconds between calls (defaults to 0)
    #
    # Returns hash of all the profile URLs, mapped to false or a status string.
    def register(update_urls: [], remove_urls: [], delay: 0)
      if update_urls.empty? && remove_urls.empty?
        Log.warn "No profiles to update or remove"
        return {}
      end

      statuses = {}
      Log.info "Registering #{update_urls.size} initiatives "+
               "and removing #{remove_urls.size} on murmuations index at #{@register_url}"

      # Remove profiles
      remove_urls.each do |url|
        sleep(delay)
        node_id = Sha256.hexdigest(url)
        statuses[url] = remove(node_id)
      end
      
      # Update profiles
      update_urls.each do |url|
        sleep(delay)
        statuses[url] = update(url)
      end

      failed = statuses.filter do |url, status|
        status == false
      end
      
      unless failed.empty?
        reason = "failed to successfully update or remove #{failed.size} profiles"
        Log.error reason
      end

      return statuses
    end



    # This validates the fields conform to the schema specification,
    # truncating selected text fields if they can be, omitting others
    # if empty, but it may also raise an exception if there is some
    # inconsistency (e.g. a locality without a country code).
    def self.write(uri_base, fields, output_file)
      # Fields expected:
      # Identifier,Name,Description,Organisational Structure,Primary Activity,Activities,Street Address,Locality,Region,Postcode,Country ID,Territory ID,Website,Phone,Email,Twitter,Facebook,Companies House Number,Qualifiers,Membership Type,Latitude,Longitude,Geo Container,Geo Container Latitude,Geo Container Longitude
      raise "No Identifier field!" unless fields.has_key? 'Identifier'
      dataset_uri = File.join(uri_base, '') # URL needs trailing slash
      org_uri = File.join(uri_base, fields['Identifier'])
      # primary_url is mandatory in the organizations_schema (at time of writing)
      # So use org_uri as a fallback option, else profile won't register.
      primary_url = fields['Website'].to_s
      primary_url = org_uri if primary_url == ''
      data = {
        linked_schemas: %w(organizations_schema-v1.0.0),
        name: fields['Name']&.to_s.strip.slice(0, 100),
        # nickname:
        primary_url: primary_url, 
        tags: [
          'https://digitalcommons.coop/mykomaps/',
          dataset_uri,
        ],
        urls: [
          {
            name: 'created by',
            url: 'https://digitalcommons.coop/mykomaps/',
          },
          {
            name: 'linked-data organisation uri',
            url: org_uri,
          },
          {
            name: 'linked-data dataset uri',
            url: dataset_uri,
          },
        ],
        description: fields['Description']&.to_s,
        # mission:
        # status: 
        full_address: to_full_address(fields),
        country_iso_3166: fields['Country ID'],
        geolocation: to_geolocation(fields),
        # image:
        # header_image:
        # images:
        # rss:
        # relationships:
        # starts_at:
        # ends_at:
        contact_details: to_contact_details(fields),
        telephone: fields['Phone'],
        # geographic_scope: 
      }.delete_if {|k, v| v == nil || v.size == 0 }
      
      IO.write(output_file, JSON.pretty_generate(data))
    end

    def self.to_contact_details(fields)
      if fields['Email'].to_s.length > 0
        {
          email: fields['Email'],
          # contact_form:
        }
      else
        nil
      end
    end
    
    def self.to_full_address(fields)
      location = [
        fields['Street Address'].to_s,
        fields['Locality'].to_s,
        fields['Region'].to_s,
        NormalizeCountry(fields['Country ID'], to: :short).to_s,
      ].filter {|v| v.size > 0 }
      return location.join(', ')
    end

    def self.to_geolocation(fields)
      loc = [fields.fetch_values('Latitude', 'Longitude'),
             fields.fetch_values('Geo Container Latitude', 'Geo Container Longitude')]
              .map {|loc| loc.map &:to_f }
              .reject {|loc| loc == [0,0] }
              .first {|loc| loc.compact.size == 2}
      return nil unless loc
      return {lat: loc[0], lon: loc[1]}
    end
    
    def self.to_org_type_tags(fields)
      ids = fields['Organisational Structure'].to_s.split(";") + [fields['Qualifiers']]
      ids
        .map {|f| f.to_s.strip.slice(0, 100) } # normalise
        .reject {|f| f.size == 0}
      # FIXME expand?
    end
    
  end
end
