//
//  WeatherViewModel.swift
//  DatWeatherDoe
//
//  Created by Inder Dhir on 1/9/22.
//  Copyright © 2022 Inder Dhir. All rights reserved.
//

import Combine
import CoreLocation
import Foundation
import OSLog

final class WeatherViewModel: WeatherViewModelType, ObservableObject {
    private let locationFetcher: SystemLocationFetcherType
    private var weatherFactory: WeatherRepositoryFactoryType
    private let configManager: ConfigManagerType
    private let logger: Logger
    private var reachability: NetworkReachability!

    private let weatherTimerSerialQueue = DispatchQueue(label: "Weather Timer Serial Queue")
    private let forecaster = WeatherForecaster()
    private var weatherTask: Task<Void, Never>?
    private var weatherTimer: Timer?
    private var weatherTimerTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    
    @Published var menuOptionData: MenuOptionData?
    @Published var weatherResult: Result<WeatherData, Error>?

    init(
        locationFetcher: SystemLocationFetcher,
        weatherFactory: WeatherRepositoryFactoryType,
        configManager: ConfigManagerType,
        logger: Logger
    ) {
        self.locationFetcher = locationFetcher
        self.configManager = configManager
        self.weatherFactory = weatherFactory
        self.logger = logger
        
        setupLocationFetching()
        setupReachability()
    }

    deinit {
        weatherTimer?.invalidate()
        weatherTask?.cancel()
    }
    func getUpdatedWeatherAfterRefresh() {
          // TODO: Use AsyncSequence
          weatherTimerTask?.cancel()
          weatherTimerTask = Task { [weak self] in
              guard let self else { return }
              
              while !Task.isCancelled {
                  self.getWeatherWithSelectedSource()
                  try? await Task.sleep(for: .seconds(configManager.refreshInterval))
              }
          }
      }

    func seeForecastForCurrentCity() {
        forecaster.seeForecastForCity()
    }

    private func setupLocationFetching() {
        locationFetcher.locationResult
            .sink(receiveValue: { [weak self] result in
                guard let self else { return }

                switch result {
                case let .success(location):
                    self.getWeather(
                        repository: weatherFactory.create(location: location),
                        unit: measurementUnit
                    )
                case let .failure(error):
                    updateWeatherData(error)
                }
            })
            .store(in: &cancellables)
    }
    
    private func setupReachability() {
         reachability = NetworkReachability(
             logger: logger,
             onBecomingReachable: { [weak self] in
                 self?.getUpdatedWeatherAfterRefresh()
             }
         )
     }

    private func getWeatherWithSelectedSource() {
        let weatherSource = WeatherSource(rawValue: configManager.weatherSource) ?? .location

        switch weatherSource {
        case .location:
            getWeatherAfterUpdatingLocation()
        case .latLong:
            getWeatherViaLocationCoordinates()
        }
    }

    private func getWeatherAfterUpdatingLocation() {
        locationFetcher.startUpdatingLocation()
    }

    private func getWeatherViaLocationCoordinates() {
        let latLong = configManager.weatherSourceText
//        guard let latLong = configManager.weatherSourceText else {
//            weatherResult = .failure(WeatherError.latLongIncorrect)
//            return
//        }

        getWeather(
            repository: weatherFactory.create(latLong: latLong),
            unit: measurementUnit
        )
    }

    private func buildWeatherDataOptions(for unit: MeasurementUnit) -> WeatherDataBuilder.Options {
        .init(
            unit: unit,
            showWeatherIcon: configManager.isShowingWeatherIcon,
            textOptions: buildWeatherTextOptions(for: unit)
        )
    }

    private func buildWeatherTextOptions(for unit: MeasurementUnit) -> WeatherTextBuilder.Options {
        let conditionPosition = WeatherConditionPosition(rawValue: configManager.weatherConditionPosition)
            ?? .beforeTemperature
        return .init(
            isWeatherConditionAsTextEnabled: configManager.isWeatherConditionAsTextEnabled,
            conditionPosition: conditionPosition,
            valueSeparator: configManager.valueSeparator,
            temperatureOptions: .init(
                unit: unit.temperatureUnit,
                isRoundingOff: configManager.isRoundingOffData,
                isUnitLetterOff: configManager.isUnitLetterOff,
                isUnitSymbolOff: configManager.isUnitSymbolOff
            ),
            isShowingHumidity: configManager.isShowingHumidity
        )
    }

    private func getWeather(repository: WeatherRepositoryType, unit: MeasurementUnit) {
        weatherTask = Task {
            do {
                let response = try await repository.getWeather()
                let weatherData = buildWeatherDataWith(
                    response: response,
                    options: buildWeatherDataOptions(for: unit)
                )
                
                updateWeatherData(weatherData)
            } catch {
                updateWeatherData(error)
            }
        }
    }

    private var measurementUnit: MeasurementUnit {
        MeasurementUnit(rawValue: configManager.measurementUnit) ?? .imperial
    }

    private func buildWeatherDataWith(
        response: WeatherAPIResponse,
        options: WeatherDataBuilder.Options
    ) -> WeatherData {
        WeatherDataBuilder(
            response: response,
            options: options,
            logger: logger
        ).build()
    }
    
    private func updateWeatherData(_ data: WeatherData) {
        DispatchQueue.main.async { [weak self] in
            self?.updateReadOnlyData(weatherData: data)
            self?.weatherResult = .success(data)
        }
    }
    
    private func updateWeatherData(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.menuOptionData = nil
            self?.weatherResult = .failure(error)
        }
    }
    
    // MARK: FIX
    
    private func updateReadOnlyData(weatherData: WeatherData) {
        let locationTitle = [
            getLocationFrom(weatherData: weatherData),
            getConditionItemFrom(weatherData: weatherData)
        ].joined(separator: " - ")
        let temperatureForecastTitle = getWeatherTextFrom(weatherData: weatherData)
        let sunriseSetTitle = getSunRiseSetFrom(weatherData: weatherData)
        let windSpeedTitle = getWindSpeedItemFrom(data: weatherData.response.windData)
        
        menuOptionData = MenuOptionData(
            locationText: locationTitle,
            weatherText: temperatureForecastTitle,
            sunriseSunsetText: sunriseSetTitle,
            tempHumidityWindText: windSpeedTitle
        )
    }
    
    private func getLocationFrom(weatherData: WeatherData) -> String {
        weatherData.response.locationName
    }
    
    private func getConditionItemFrom(weatherData: WeatherData) -> String {
        WeatherConditionTextMapper().map(weatherData.weatherCondition)
    }
    
    private func getWeatherTextFrom(weatherData: WeatherData) -> String {
        let measurementUnit = MeasurementUnit(rawValue: configManager.measurementUnit) ?? .imperial
        
        return TemperatureForecastTextBuilder(
            temperatureData: weatherData.response.temperatureData,
            forecastTemperatureData: weatherData.response.forecastDayData.temp,
            options: .init(
                unit: measurementUnit.temperatureUnit,
                isRoundingOff: configManager.isRoundingOffData,
                isUnitLetterOff: configManager.isUnitLetterOff,
                isUnitSymbolOff: configManager.isUnitSymbolOff
            )
        ).build()
    }
    
    private func getSunRiseSetFrom(weatherData: WeatherData) -> String {
        SunriseAndSunsetTextBuilder(
            sunset: weatherData.response.forecastDayData.astro.sunset,
            sunrise: weatherData.response.forecastDayData.astro.sunrise
        ).build()
    }
    
    private func getWindSpeedItemFrom(data: WindData) -> String {
        if configManager.measurementUnit == MeasurementUnit.all.rawValue {
            WindSpeedFormatter()
                .getFormattedWindSpeedStringForAllUnits(
                    windData: data,
                    isRoundingOff: configManager.isRoundingOffData
                )
        } else {
            WindSpeedFormatter()
                .getFormattedWindSpeedString(
                    unit: MeasurementUnit(rawValue: configManager.measurementUnit) ?? .imperial,
                    windData: data
                )
        }
    }
}
