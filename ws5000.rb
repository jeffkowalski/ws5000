#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

# rubocop: disable Layout/ExtraSpacing, Layout/CommentIndentation, Layout/HashAlignment
FIELD_TRANSFORMS  = {
#  ws5000                   type,        rename                                 description
#  -------------------    ----------------------------------------------------  ----------------------------------------
  'stationtype'        => { type: nil,   name: nil },                           # "stationtype"=>"AMBWeatherV4.3.4",
  'PASSKEY'            => { type: nil,   name: nil },                           # "PASSKEY"=>"98:CD:AC:22:F4:37",
  'dateutc'            => { type: nil,   name: nil },                           # "dateutc"=>"2023-02-22 19:58:42",
  'tempinf'            => { type: :to_f, name: 'temperature_indoor' },          # "tempinf"=>"65.8",
  'battin'             => { type: :to_i, name: 'battery_indoor' },              # "battin"=>"1",
  'humidityin'         => { type: :to_i, name: 'humidity_indoor' },             # "humidityin"=>"37",
  'baromrelin'         => { type: :to_f, name: 'pressure_relative' },           # "baromrelin"=>"29.126",
  'baromabsin'         => { type: :to_f, name: 'pressure_absolute' },           # "baromabsin"=>"29.126",
  'tempf'              => { type: :to_f, name: 'temperature_outdoor' },         # "tempf"=>"46.4",
  'battout'            => { type: :to_i, name: 'battery_outdoor' },             # "battout"=>"1",
  'battrain'           => { type: :to_i, name: 'battery_rain' },                # "battrain"=>"1",
  'humidity'           => { type: :to_i, name: 'humidity_outdoor' },            # "humidity"=>"48",
  'winddir'            => { type: :to_i, name: 'wind_direction' },              # "winddir"=>"283",
  'winddir_avg10m'     => { type: :to_i, name: 'wind_direction_average_10m' },  # "winddir_avg10m"=>"276",
  'windspeedmph'       => { type: :to_f, name: 'wind_speed' },                  # "windspeedmph"=>"16.3",
  'windspdmph_avg10m'  => { type: :to_f, name: 'wind_gust_average_10m' },       # "windspdmph_avg10m"=>"10.1",
  'windgustmph'        => { type: :to_f, name: 'wind_gust' },                   # "windgustmph"=>"20.8",
  'maxdailygust'       => { type: :to_f, name: 'wind_gust_max_daily' },         # "maxdailygust"=>"28.4",
  'eventrainin'        => { type: :to_f, name: 'rain_event' },                  # "hourlyrainin"=>"0.000",
  'dailyrainin'        => { type: :to_f, name: 'rain_daily' },                  # "eventrainin"=>"0.000",
  'hourlyrainin'       => { type: :to_f, name: 'rain_hourly' },                 # "dailyrainin"=>"0.000",
  'weeklyrainin'       => { type: :to_f, name: 'rain_weekly' },                 # "weeklyrainin"=>"0.075",
  'monthlyrainin'      => { type: :to_f, name: 'rain_monthly' },                # "monthlyrainin"=>"1.339",
  'yearlyrainin'       => { type: :to_f, name: 'rain_yearly' },                 # "yearlyrainin"=>"1.461",
  'solarradiation'     => { type: :to_f, name: 'solar_radiation' },             # "solarradiation"=>"278.93",
  'uv'                 => { type: :to_i, name: 'uv_index' },                    # "uv"=>"2",
  'batt_co2'           => { type: :to_i, name: 'battery_co2' }                  # "batt_co2"=>"1"
}.freeze
# rubocop: enable Layout/ExtraSpacing, Layout/CommentIndentation, Layout/HashAlignment

TCPPORT = 8080

class WS5000 < RecorderBotBase
  no_commands do
    # in contrast to "main" functions in other bots, this one runs forever
    def main
      addr = Socket.ip_address_list.detect(&:ipv4_private?).ip_address
      server = WEBrick::HTTPServer.new(BindAddress: addr, Port: TCPPORT)

      server.mount_proc '/data/report' do |request, response|
        path = request.path
        # in v4.2.8 the path is automatically set to /data/report/ without a ? - so fix this first
        path.gsub!(%r{/data/report/}, '$1?') unless path.include?('?')
        url = Addressable::URI.parse(path)
        query = url.query_values

        timestamp = DateTime.parse(query['dateutc']).to_time.to_i

        data = []
        query.each_pair do |key, value|
          unless FIELD_TRANSFORMS.key?(key)
            @logger.error "unrecognized field #{key}"
            next
          end

          transform = FIELD_TRANSFORMS[key]
          @logger.info key.ljust(19) + transform[:name].to_s.ljust(27) + value.to_s

          next if value.nil? || transform[:name].nil?

          datum = { series: transform[:name],
                    values: { value: value.send(transform[:type]) },
                    timestamp: timestamp }
          data.push datum
        end

        influxdb = InfluxDB::Client.new 'wxdata' unless options[:dry_run]
        influxdb.write_points data unless options[:dry_run]

        response.status = 200
      end

      trap('INT') { server.shutdown }

      server.start
    end
  end
end

WS5000.start
