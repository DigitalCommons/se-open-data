# coding: utf-8
require 'se_open_data/utils/digest_index'
require 'minitest/autorun'
require 'linkeddata'

# Tests for SeOpenData::VocabToIndex.

Minitest::Test::make_my_diffs_pretty!

describe SeOpenData::Utils::DigestIndex do

  describe "parse_str" do

    di = SeOpenData::Utils::DigestIndex.new

    it "parse_str should read a file correctly" do
      di.parse_str(<<HERE)
Key	Digest
10	RCaV09yn9Ms2PGBOEsO0AxQB9doWy1AUm-VBBdgkOao
100	aIWs68EVNqsh83NDxp9orVKLnxcOmB6vpYFd0K7jd7Q
102	
105	W7eMOYqJnkxAUnkECjgejW0OkacnW6Uz907KFoOQDog
107	La_tFTNAgjTQqcBc8qzdF324fMi89Z-3UO2FnQ1pNFM
109
HERE
      value(di.index).must_equal(
        [
          ['10', 'RCaV09yn9Ms2PGBOEsO0AxQB9doWy1AUm-VBBdgkOao'],
          ['100', 'aIWs68EVNqsh83NDxp9orVKLnxcOmB6vpYFd0K7jd7Q'],
          ['102', ''],
          ['105', 'W7eMOYqJnkxAUnkECjgejW0OkacnW6Uz907KFoOQDog'],
          ['107', 'La_tFTNAgjTQqcBc8qzdF324fMi89Z-3UO2FnQ1pNFM'],
          ['109', ''],
        ]
      )

    end
  end
end
