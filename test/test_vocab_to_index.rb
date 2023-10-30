# coding: utf-8
require 'se_open_data/vocab_to_index'
require 'minitest/autorun'
require 'linkeddata'

# Tests for SeOpenData::VocabToIndex.

Minitest::Test::make_my_diffs_pretty!

def read_ttl(filestem)
  data_dir = __dir__+"/data"
  v2i = nil
  RDF::Reader.open(data_dir + '/' + filestem + '.ttl') do |reader|
    v2i = SeOpenData::VocabToIndex.new(reader.to_enum)
  end
  v2i
end

def empty_vocab_index(languages = [])
  {
    prefixes: {},
    meta: {
      vocab_srcs: [],
      languages: languages,
      queries: [],
    },
    vocabs: {},
  }
end

describe SeOpenData::VocabToIndex do
  
  describe "using activities.ttl" do
    v2j = read_ttl('activities')

    it "an empty config should result in an empty index" do
      result = v2j.aggregate({
                               languages: [], # empty means "whatever you got"
                               vocabularies: [],
                             })
      #puts JSON.pretty_generate(result)
      #puts result.inspect
      value(result).must_equal(empty_vocab_index([:EN, :ES, :FR, :KO, :PT]))
    end


    it "a single english vocab request should result in an english index" do
      result = v2j.aggregate({
                               languages: [:EN],
                               vocabularies: [
                                 { uris: {
                                     "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities/" => "aci",
                                   }
                                 }
                               ],
                             })
      #puts JSON.pretty_generate(result)
      #puts result.inspect
      value(result).must_equal(
        {
          prefixes: {
            "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities/" => :aci,
          },
          meta: {
            vocab_srcs: [
              { uris: {
                  "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities/" => "aci",
                }
              }
            ],
            languages: [:EN],
            queries: [],
          },
          vocabs: {
            "aci:": {
                      :EN=>{
                        :terms=>{
                          "aci:a01": "Agriculture and environment",
                          "aci:a02": "Mining and quarrying",
                          "aci:a03": "Craftmanship and manufacturing",
                          "aci:a04": "Energy production and distribution",
                          "aci:a05": "Recycling, waste treatment, water cycle and ecological restoration",
                          "aci:a06": "Construction, public works and refurbishing",
                          "aci:a07": "Trade and distribution",
                          "aci:a08": "Transport, logistics and storage",
                          "aci:a09": "Hospitality and food service activities",
                          "aci:a10": "Information, communication and technologies",
                          "aci:a11": "Financial, insurance and related activities",
                          "aci:a12": "Habitat and housing",
                          "aci:a13": "Professional, scientific and technical activities",
                          "aci:a14": "Administration and management, tourism, rentals",
                          "aci:a15": "Public administration and social security",
                          "aci:a16": "Education and training",
                          "aci:a17": "Social services, health and employment",
                          "aci:a18": "Arts, culture, recreation and sports",
                          "aci:a19": "Membership activities, repairing and wellness",
                          "aci:a20": "Household activities, self-production, domestic work",
                          "aci:a21": "International diplomacy and cooperation"
                        },
                        :title=>"Activities"
                      },
                    },
          },
        }
      )
    end


    it "conflicting uris in vocab request fail, catching all the right cases" do
      err = value(
        proc {
          v2j.aggregate(
            {
              languages: [],
              vocabularies: [
                { uris: {
                    "https://dev.lod.coop/essglobal/2.1/standard/activities/" => "ac",
                    "https://dev.lod.coop/essglobal/2.1/standard/organisations/" => "os",
                    # dupe prefix in same vocab - bad
                    "https://dev.lod.coop/essglobal/2.1/standard/organisation/" => "os",
                    "https://dev.lod.coop/essglobal/2.1/standard/membership/" => "mm",
                    
                  } },
                { uris: {
                    # dupe uri in separate vocab - bad
                    "https://dev.lod.coop/essglobal/2.1/standard/organisations/" => "orgs",
                    # dupe prefix in separate vocab -  bad
                    "https://dev.lod.coop/essglobal/2.1/standard/accounting/" => "ac",
                    # dupe both prefix and uri - ok
                    "https://dev.lod.coop/essglobal/2.1/standard/membership/" => "mm",
                  } },
              ],
            }
          )
        }
      ).must_raise(ArgumentError)

      value(err.message).must_match(
        %r{.*: os, ac, https://dev.lod.coop/essglobal/2.1/standard/organisations/}
      )
    end


    it "this fairly typical config should generate the expcted vocab datastructure" do
      result = v2j.aggregate({
                               languages: [:EN, :FR],
                               vocabularies: [
                                 { uris: {
                                     "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities/" => "aci",
                                     "https:\/\/dev.lod.coop/essglobal/2.1/standard/base-membership-type/" => "bmt",
                                   }
                                 }
                               ],
                             })
      #puts JSON.pretty_generate(result)
      #puts result.inspect
      value(result).must_equal(
        {
          :prefixes=>{
            "https://dev.lod.coop/essglobal/2.1/standard/activities/" => :aci,
            "https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/" => :bmt,
          },
          :meta=>{
            :vocab_srcs=>[
              {
                :uris=>{
                  "https://dev.lod.coop/essglobal/2.1/standard/activities/"=>"aci",
                  "https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/"=>"bmt"
                }
              }
            ],
            :languages=>[:EN, :FR], # Note, lowercase, because from input config. FIXME
            :queries=>[]
          },
          :vocabs=>{
            "aci:": {
                      :EN=>{
                        :terms=>{
                          "aci:a01": "Agriculture and environment",
                                 "aci:a02": "Mining and quarrying",
                                 "aci:a03": "Craftmanship and manufacturing",
                                 "aci:a04": "Energy production and distribution",
                                 "aci:a05": "Recycling, waste treatment, water cycle and ecological restoration",
                                 "aci:a06": "Construction, public works and refurbishing",
                                 "aci:a07": "Trade and distribution",
                                 "aci:a08": "Transport, logistics and storage",
                                 "aci:a09": "Hospitality and food service activities",
                                 "aci:a10": "Information, communication and technologies",
                                 "aci:a11": "Financial, insurance and related activities",
                                 "aci:a12": "Habitat and housing",
                                 "aci:a13": "Professional, scientific and technical activities",
                                 "aci:a14": "Administration and management, tourism, rentals",
                                 "aci:a15": "Public administration and social security",
                                 "aci:a16": "Education and training",
                                 "aci:a17": "Social services, health and employment",
                                 "aci:a18": "Arts, culture, recreation and sports",
                                 "aci:a19": "Membership activities, repairing and wellness",
                                 "aci:a20": "Household activities, self-production, domestic work",
                                 "aci:a21": "International diplomacy and cooperation"
                        },
                        :title=>"Activities"
                      },
                      :FR=>{
                        :terms=>{
                          "aci:a01": "Agriculture et environnement",
                                 "aci:a02": "Mines et carrières",
                                 "aci:a03": "Artisanat et manifacturier",
                                 "aci:a04": "production et distribution de l'énergie",
                                 "aci:a05": "Recyclage, traitement des déchets, cycle de l'eau et la restauration écologique",
                                 "aci:a06": "Construction, travaux publics et remise à neuf",
                                 "aci:a07": "Commerce et distribution",
                                 "aci:a08": "Transport, logistique et entreposage",
                                 "aci:a09": "Restauration, hôtellerie, catering",
                                 "aci:a10": "Information, communication et technologies",
                                 "aci:a11": "Finance, assurance et activités connexes",
                                 "aci:a12": "Habitat et logement",
                                 "aci:a13": "Activités professionnelles, scientifiques et techniques",
                                 "aci:a14": "Administration et mangement, tourisme et location",
                                 "aci:a15": "Administration publique et sécurité sociale",
                                 "aci:a16": "Éducation et formation",
                                 "aci:a17": "Services sociaux et santé",
                                 "aci:a18": "Art, culture, loisirs et sports",
                                 "aci:a19": "", "aci:a20": "", "aci:a21": ""
                        },
                        :title=>""
                      }
                    }
          }
        }
      )
    end
  end

  describe "using activities-modified.ttl" do

    # Activites modified has blank language values
    
    v2j = read_ttl('activities-modified');

    it "an empty config should result in an empty index" do
      result = v2j.aggregate({
                               languages: [], # empty means "whatever you got"
                               vocabularies: [],
                             })
      #puts JSON.pretty_generate(result)
      #puts result.inspect
      value(result).must_equal(empty_vocab_index([:EN, :ES, :FR, :KO, :PT]))
    end


    it "a single english vocab request should result in an english index" do
      result = v2j.aggregate({
                               languages: [:EN],
                               vocabularies: [
                                 { uris: {
                                     "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities-modified/" => "am",
                                   }
                                 }
                               ],
                             })
      #puts JSON.pretty_generate(result)
      #puts result.inspect
      value(result).must_equal(
        {
          prefixes: {
            "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities-modified/" => :am,
          },
          meta: {
            vocab_srcs: [
              { uris: {
                  "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities-modified/" => "am",
                }
              }
            ],
            languages: [:EN],
            queries: [],
          },
          vocabs: {
            "am:": {
                     :EN=>{
                       :title=>"Activities (Modified)",
                       :terms=> {
                                 "am:AM10": "Arts, Media, Culture & Leisure",
                                 "am:AM20": "Campaigning, Activism & Advocacy",
                                 "am:AM30": "Community & Collective Spaces",
                                 "am:AM40": "Education",
                                 "am:AM50": "Energy",
                                 "am:AM60": "Food",
                                 "am:AM70": "Goods & Services",
                                 "am:AM80": "Health, Social Care & Wellbeing",
                                 "am:AM90": "Housing",
                                 "am:AM100": "Money & Finance",
                                 "am:AM110": "Nature, Conservation & Environment",
                                 "am:AM120": "Reduce, Reuse, Repair & Recycle",
                                 "am:AM130": "Agriculture",
                                 "am:AM140": "Industry",
                                 "am:AM150": "Utilities",
                                 "am:AM160": "Transport",
                       },
                       
                     },
                   },
          }
        }
      )
    end
    
    it "an empty vocab request should result in all indexes" do
      # And complete indexes, even if there are missing items in some cases.
      # Fill in the gaps with ""
      
      result = v2j.aggregate({
                               vocabularies: [
                                 { uris: {
                                     "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities-modified/" => "am",
                                   }
                                 }
                               ],
                             })
      #puts JSON.pretty_generate(result)
      # pp result
      value(result).must_equal(
        {
          prefixes: {
            "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities-modified/" => :am,
          },
          meta: {
            vocab_srcs: [
              { uris: {
                  "https:\/\/dev.lod.coop/essglobal/2.1/standard/activities-modified/" => "am",
                }
              }
            ],
            languages: [:EN, :ES, :FR, :KO, :PT],
            queries: [],
          },
          vocabs: {
              "am:": {
                       EN: {
                         title: "Activities (Modified)",
                         terms:
                           {
                             "am:AM10": "Arts, Media, Culture & Leisure",
                            "am:AM100": "Money & Finance",
                            "am:AM110": "Nature, Conservation & Environment",
                            "am:AM120": "Reduce, Reuse, Repair & Recycle",
                            "am:AM130": "Agriculture",
                            "am:AM140": "Industry",
                            "am:AM150": "Utilities",
                            "am:AM160": "Transport",
                            "am:AM20": "Campaigning, Activism & Advocacy",
                            "am:AM30": "Community & Collective Spaces",
                            "am:AM40": "Education",
                            "am:AM50": "Energy",
                            "am:AM60": "Food",
                            "am:AM70": "Goods & Services",
                            "am:AM80": "Health, Social Care & Wellbeing",
                            "am:AM90": "Housing"}},
                       ES: 
                         {
                           title: "Activities (Modified)",
                           terms: 
                             {
                               "am:AM10": "",
                              "am:AM100": "",
                              "am:AM110": "",
                              "am:AM120": "",
                              "am:AM130": "",
                              "am:AM140": "",
                              "am:AM150": "",
                              "am:AM160": "",
                              "am:AM20": "",
                              "am:AM30": "",
                              "am:AM40": "",
                              "am:AM50": "",
                              "am:AM60": "",
                              "am:AM70": "",
                              "am:AM80": "",
                              "am:AM90": ""
                             }
                         },
                       FR: 
                         {
                           title: "Activities (Modified)",
                           terms: 
                             {
                               "am:AM10": "",
                              "am:AM100": "",
                              "am:AM110": "",
                              "am:AM120": "",
                              "am:AM130": "",
                              "am:AM140": "",
                              "am:AM150": "",
                              "am:AM160": "",
                              "am:AM20": "",
                              "am:AM30": "",
                              "am:AM40": "",
                              "am:AM50": "",
                              "am:AM60": "",
                              "am:AM70": "",
                              "am:AM80": "",
                              "am:AM90": ""
                             }
                         },
                       KO: 
                         {
                           title: "Activities (Modified)",
                           terms: 
                             {
                               "am:AM10": "",
                              "am:AM100": "",
                              "am:AM110": "",
                              "am:AM120": "",
                              "am:AM130": "",
                              "am:AM140": "",
                              "am:AM150": "",
                              "am:AM160": "",
                              "am:AM20": "",
                              "am:AM30": "",
                              "am:AM40": "",
                              "am:AM50": "",
                              "am:AM60": "",
                              "am:AM70": "",
                              "am:AM80": "",
                              "am:AM90": ""
                             }
                         },
                       PT: 
                         {
                           title: "Activities (Modified)",
                           terms: 
                             {
                               "am:AM10": "",
                              "am:AM100": "",
                              "am:AM110": "",
                              "am:AM120": "",
                              "am:AM130": "",
                              "am:AM140": "",
                              "am:AM150": "",
                              "am:AM160": "",
                              "am:AM20": "",
                              "am:AM30": "",
                              "am:AM40": "",
                              "am:AM50": "",
                              "am:AM60": "",
                              "am:AM70": "",
                              "am:AM80": "",
                              "am:AM90": ""
                             }
                         }
                     }
          }
        }
      )
    end
  end

end
# FIXME test case of ttl lang tags
