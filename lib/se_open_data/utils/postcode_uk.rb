
module SeOpenData::Utils
  class PostcodeUk

    # Checks whether the parameter is considerd a valid postcode
    def self.valid?(s)
      @@uk_postcode_regex.match(s)
    end
    
    @@uk_postcode_regex = /([Gg][Ii][Rr] 0[Aa]{2})|((([A-Za-z][0-9]{1,2})|(([A-Za-z][A-Ha-hJ-Yj-y][0-9]{1,2})|(([A-Za-z][0-9][A-Za-z])|([A-Za-z][A-Ha-hJ-Yj-y][0-9][A-Za-z]?))))\s?[0-9][A-Za-z]{2})/

  end
end
