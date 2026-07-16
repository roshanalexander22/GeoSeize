import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherInfo {
  final double temperature;
  final int humidity;
  final double rainProbability; // percentage
  final double windSpeed; // km/h
  final String condition;
  final int weatherCode;

  const WeatherInfo({
    required this.temperature,
    required this.humidity,
    required this.rainProbability,
    required this.windSpeed,
    required this.condition,
    required this.weatherCode,
  });

  factory WeatherInfo.mock() {
    return const WeatherInfo(
      temperature: 28.5,
      humidity: 65,
      rainProbability: 20.0,
      windSpeed: 12.5,
      condition: 'Clear Sky',
      weatherCode: 0,
    );
  }
}

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  /// Map WMO weather code to user-friendly description
  /// Reference: WMO weather interpretation codes
  String _mapWeatherCode(int code) {
    if (code == 0) return 'Clear Sky';
    if (code >= 1 && code <= 3) return 'Partly Cloudy';
    if (code == 45 || code == 48) return 'Foggy';
    if (code >= 51 && code <= 55) return 'Light Drizzle';
    if (code >= 56 && code <= 57) return 'Freezing Drizzle';
    if (code >= 61 && code <= 65) return 'Rainy';
    if (code >= 66 && code <= 67) return 'Freezing Rain';
    if (code >= 71 && code <= 75) return 'Snowy';
    if (code == 77) return 'Snow Grains';
    if (code >= 80 && code <= 82) return 'Rain Showers';
    if (code >= 85 && code <= 86) return 'Snow Showers';
    if (code == 95) return 'Thunderstorm';
    if (code >= 96 && code <= 99) return 'Severe Thunderstorm';
    return 'Cloudy';
  }

  Future<WeatherInfo> fetchWeather(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?'
        'latitude=$lat&longitude=$lng'
        '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m'
        '&hourly=precipitation_probability&forecast_days=1'
      );

      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        
        // Fetch current hourly precipitation probability (defaulting to 0 if not found)
        double rainProb = 0.0;
        final hourly = data['hourly'];
        if (hourly != null && hourly['precipitation_probability'] is List) {
          final List probs = hourly['precipitation_probability'];
          if (probs.isNotEmpty) {
            rainProb = (probs[0] as num).toDouble();
          }
        }

        final double temp = (current['temperature_2m'] as num).toDouble();
        final int hum = (current['relative_humidity_2m'] as num).toInt();
        final int code = (current['weather_code'] as num).toInt();
        final double wind = (current['wind_speed_10m'] as num).toDouble();

        return WeatherInfo(
          temperature: temp,
          humidity: hum,
          rainProbability: rainProb,
          windSpeed: wind,
          condition: _mapWeatherCode(code),
          weatherCode: code,
        );
      }
    } catch (e) {
      // Gracefully swallow network/timeout errors and return mock data
      print('Weather Service Error: $e');
    }
    return WeatherInfo.mock();
  }
}
