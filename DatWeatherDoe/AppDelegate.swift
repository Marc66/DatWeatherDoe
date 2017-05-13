//
//  AppDelegate.swift
//  DatWeatherDoe
//
//  Created by Inder Dhir on 1/19/16.
//  Copyright © 2016 Inder Dhir. All rights reserved.
//

import Cocoa
import CoreLocation

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var window: NSWindow!

    let darkMode = "Dark"
    let weatherService = WeatherService()
    let locationManager = CLLocationManager()
    let locationTimerInterval = TimeInterval(900)
    var locationTimer: Timer?
    let statusItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)

    var firstTimeLocationUse: Bool = false
    var weatherTimer: Timer?
    var currentTempString: String?
    var currentIconString: String?
    var currentImageData: NSImage?
    var currentLocation: CLLocationCoordinate2D?
    let popover = NSPopover()
    var zipCode: String?
    var refreshInterval: TimeInterval?
    var unit: String?
    var locationUsed: Bool = false
    var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        // Check if dark/light mode
        let appearance = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
        weatherService.darkModeOn = (appearance == darkMode)

        // Location
        firstTimeLocationUse = true
        locationManager.delegate = self

        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 3000 // Only worry about location distance above 3 km

        self.locationTimer = createLocationTimer()

        // Defaults
        self.zipCode = DefaultsChecker.getDefaultZipCode()
        self.refreshInterval = DefaultsChecker.getDefaultRefreshInterval()
        self.unit = DefaultsChecker.getDefaultUnit()
        self.locationUsed = DefaultsChecker.getDefaultLocationUsedToggle()

        // Menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(getWeather), keyEquivalent: "R"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Configure", action: #selector(togglePopover), keyEquivalent: "C"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(terminate), keyEquivalent: "q"))
        statusItem.menu = menu

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
        }
        popover.contentViewController =
            ConfigureViewController(nibName: "ConfigureViewController", bundle: nil)

        // Weather Timer
        self.weatherTimer = Timer.scheduledTimer(timeInterval: refreshInterval!, target: self,
                                                 selector: self.locationUsed ?
                                                    #selector(getWeatherViaLocation) :
                                                    #selector(getWeatherViaZipCode),
                                                 userInfo: nil, repeats: true)

        // Fired twice due to a bug where the icon and temperature don't display properly the first time
        self.weatherTimer!.fire()
        self.weatherTimer!.fire()

        // Event monitor to listen for clicks outside the popover
        eventMonitor = EventMonitor(mask: NSEventMask.leftMouseDown) { [unowned self] event in
            if self.popover.isShown {
                self.closePopover(event)
            }
        }
        eventMonitor?.start()
    }

    func getLocation() {
        locationManager.startUpdatingLocation()
    }

    func getWeather(_ sender: AnyObject?) {
        if locationUsed {
            getWeatherViaLocation()
        } else {
            getWeatherViaZipCode()
        }
    }

    func getWeatherViaZipCode() {
        if zipCode != nil {
            weatherService.getWeather(
            self.zipCode!, unit: self.unit!) { (currentTempString: String, iconString: String) in
                self.updateWeather(currentTempString)
                self.updateIcon(iconString)
                self.updateUI()
            }
        }
    }

    func getWeatherViaLocation() {
        if self.firstTimeLocationUse {
            getLocation()
        } else if currentLocation != nil {
            weatherService.getWeather(
            currentLocation!, unit: self.unit!) { (currentTempString: String, iconString: String) in
                self.updateWeather(currentTempString)
                self.updateIcon(iconString)
                self.updateUI()
            }
        }
    }

    func createLocationTimer() -> Timer {
        return Timer.scheduledTimer(timeInterval: locationTimerInterval, target: self,
                                    selector: #selector(getLocation), userInfo: nil, repeats: true)
    }

    func updateIcon(_ iconString: String) {
        self.currentImageData = NSImage(named: iconString)
    }

    func updateWeather(_ currentTempString: String) {
        self.currentTempString = currentTempString
    }

    func updateUI() {
        if let imageData = currentImageData {
            self.statusItem.image = imageData
        }
        if let tempString = currentTempString {
            self.statusItem.title = tempString
        }
    }

    /* Popover stuff for listening for clicks outside the configure window */
    func showPopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
        eventMonitor?.start()
    }

    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    func terminate() {
        NSApp.terminate(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // If user declines location permission
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        self.getWeatherViaZipCode()
        self.locationUsed = false
        self.locationTimer?.invalidate()

        // Remember location toggle
        DefaultsChecker.setDefaultLocationUsedToggle(false)
    }

    //CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = manager.location {
            self.currentLocation = location.coordinate

            if self.firstTimeLocationUse {
                self.firstTimeLocationUse = false
                self.getWeatherViaLocation()
            }

            // Remember location toggle
            DefaultsChecker.setDefaultLocationUsedToggle(true)
        }
    }
}
