# frozen_string_literal: true

# Kosovo uses the user-assigned code XK (not officially in ISO 3166-1, but widely recognized)
ISO3166::Data.register(
  alpha2: "XK",
  alpha3: "XKX",
  continent: "Europe",
  country_code: "383",
  currency_code: "EUR",
  distance_unit: "KM",
  gec: "KV",
  geo: {
    latitude: 42.602636,
    longitude: 20.902977,
    max_latitude: 43.2173393,
    max_longitude: 21.7899115,
    min_latitude: 41.8571425,
    min_longitude: 19.9771964,
    bounds: {
      northeast: { lat: 43.2173393, lng: 21.7899115 },
      southwest: { lat: 41.8571425, lng: 19.9771964 }
    }
  },
  international_prefix: "00",
  ioc: "KOS",
  iso_long_name: "Republic of Kosovo",
  iso_short_name: "Kosovo",
  languages_official: [ "sq", "sr" ],
  languages_spoken: [ "sq", "sr" ],
  name: "Kosovo",
  common_name: "Kosovo",
  names: [ "Kosovo" ],
  national_destination_code_lengths: [ 2 ],
  national_number_lengths: [ 8, 9 ],
  national_prefix: "0",
  nationality: "Kosovar",
  number: "926",
  postal_code: true,
  postal_code_format: "\\d{5}",
  region: "Europe",
  start_of_week: "monday",
  subregion: "Southern Europe",
  un_locode: "XK",
  un_member: false,
  unofficial_names: [ "Kosovo", "Kosova", "Република Косово", "コソボ" ],
  vat_rates: { standard: 18 },
  vehicle_registration_code: "RKS",
  world_region: "EMEA",
  translations: { en: "Kosovo" },
  translated_names: [ "Kosovo" ]
)
