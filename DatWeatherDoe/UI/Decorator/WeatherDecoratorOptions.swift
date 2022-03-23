//
//  WeatherDecoratorOptions.swift
//  DatWeatherDoe
//
//  Created by Inder Dhir on 1/9/22.
//  Copyright © 2022 Inder Dhir. All rights reserved.
//

struct WeatherDecoratorOptions {
    let temperatureUnit: TemperatureUnit
    let isWeatherConditionAsTextEnabled: Bool
    let isShowingHumidity: Bool
    let isRoundingOff: Bool
    
    func buildTemperatureDecoratorOptions(temperature: Double)
    -> TemperatureDecoratorOptions {
        .init(
            temperature: temperature,
            unit: temperatureUnit,
            isRoundingOff: isRoundingOff
        )
    }
}
