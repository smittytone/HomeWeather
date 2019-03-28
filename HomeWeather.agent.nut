// Home Weather - wall-mount weather Station
// Copyright Tony Smith, 2015-2019

// ********** IMPORTS **********
#require "Rocky.class.nut:2.0.2"
#require "DarkSky.agent.lib.nut:2.0.0"

// If you are NOT using Squinter or a similar tool, replace the following #import statement(s)
// with the contents of the named file(s):
#import "../generic/simpleslack.nut"            // Source: https://github.com/smittytone/generic
#import "../generic/crashReporter.nut"          // Source: https://github.com/smittytone/generic
#import "../Location/location.class.nut"        // Source: https://github.com/smittytone/Location
const HTML_STRING = @"
#import "homeweather_ui.html"
";                                              // Source: https://github.com/smittytone/HomeWeather


// ********** CONSTANTS **********
const RESTART_TIMEOUT = 120;
const FORECAST_REFRESH = 900;
const LOCATION_RETRY = 60;


// ********** GLOBALS **********
local request = null;
local forecaster = null;
local nextForecastTimer = null;
local agentRestartTimer = null;
local api = null;
local savedData = null;
local locator = null;
local location = null;
local settings = null;
local syncFlag = false;
local darkSkyCount = 0;


// ********** WEATHER FUNCTIONS **********
function getForecast() {
    // Request the weather data from Forecast.io asynchronously
    if (location != null && darkSkyCount < 990) {
        appLog("Requesting a forecast");
        forecaster.forecastRequest(location.longitude, location.latitude, forecastCallback);
    }

    // Check on the device
    if (!device.isconnected() && syncFlag) syncFlag = false;
}

function forecastCallback(err, data) {
    // Decode the JSON-format data from forecast.io (error thrown if invalid)
    if (err) appError(err);
    if (data) {
        appLog("Weather forecast data received from DarkSky");
        if ("hourly" in data) {
            if ("data" in data.hourly) {
                // Get second item in array: this is the weather one hour from now
                local item = data.hourly.data[1];
                local sendData = {};
                sendData.cast <- item.icon;

                // Adjust troublesome icon names
                if (item.icon == "wind") sendData.cast = "windy";
                if (item.icon == "fog") sendData.cast = "foggy";

                if (item.icon == "clear-day") {
                    item.icon = "clearday";
                    sendData.cast = "clear";
                }

                if (item.icon == "clear-night") {
                    item.icon = "clearnight";
                    sendData.cast = "clear";
                }

                if (item.icon == "partly-cloudy-day" || item.icon == "partly-cloudy-night") {
                    item.icon = "partlycloudy";
                    sendData.cast = "partly cloudy";
                }

                if (item.summary == "Drizzle" || item.summary == "Light Rain") {
                    item.icon = "lightrain";
                    sendData.cast = "drizzle";
                }

                local initial = sendData.cast.slice(0, 1);
                sendData.cast = initial.toupper() + sendData.cast.slice(1);

                // Send the icon name to the device
                sendData.icon <- item.icon;
                sendData.temp <- item.apparentTemperature;
                sendData.rain <- item.precipProbability;
                device.send("homeweather.show.forecast", sendData);
                savedData = sendData;
                appLog("Forecast: " + sendData.cast + ". Temperature: " + sendData.temp + "°C. Chance of rain: " + (sendData.rain * 100) + "%");
            }
        }

        // Use Dark Sky 2.0.0's callCount property/method
        appLog("Current Forecast API call tally: " + forecaster.callCount + "/1000 ");
        darkSkyCount = forecaster.getCallCount();
    }

    // Get the next forecast in an 'FORECAST_REFRESH' minutes' time
    if (nextForecastTimer != null) imp.cancelwakeup(nextForecastTimer);
    nextForecastTimer = imp.wakeup(FORECAST_REFRESH, getForecast);
}


// ********** INITIALISATION FUNCTIONS **********
function deviceIsReady(dummy) {
    // This is called ONLY by the device via agent.send() when it starts
    // or by the agent itself after an agent migration/restart IF the device is already connected
    if (agentRestartTimer != null) {
        // Agent started less than RESTART_TIMEOUT seconds ago
        imp.cancelwakeup(agentRestartTimer);
        agentRestartTimer = null;
    }

    // Send the device its settings
    device.send("homeweather.set.settings", settings);
    syncFlag = true;

    // Do we have a location for the device?
    if (location != null) {
        // Yes, so get a fresh forecast
        // NOTE this will be the case after device-only restarts
        if (nextForecastTimer != null) imp.cancelwakeup(nextForecastTimer);
        nextForecastTimer = imp.wakeup(0, getForecast);
    } else {
        // Get the device's location
        // NOTE this will the case after device+agent restarts
        locator.locate(true, function() {
            location = locator.getLocation();

            if (!("error" in location)) {
                // Start the forecasting loop
                appLog("Co-ordinates: " + location.longitude + ", " + location.latitude);
                if (nextForecastTimer != null) imp.cancelwakeup(nextForecastTimer);
                nextForecastTimer = imp.wakeup(0, getForecast);
            } else {
                // Device's location not obtained
                appError(location.error);

                // Clear 'location' to force the code to try to get it again
                location = null;

                // Check again in LOCATION_RETRY seconds
                imp.wakeup(LOCATION_RETRY, function() { 
                    deviceIsReady(true);
                });
            }
        });
    }
}

function initialiseSettings() {
    // Reset the settings to the defaults
    // First clear the saved data in case the settings keys have changed
    server.save({});

    // Create a new settings table
    settings = {};
    settings.dimstart <- 22;
    settings.dimend <- 7;
    settings.offatnight <- false;
    settings.debug <- false;

    // Save the new table
    server.save(settings);
}


// ********** LOGGING FUNCTIONS **********
function appLog(message) {
    if (settings.debug) server.log(message);
}

function appError(message) {
    if (settings.debug) server.error(message);
}

function debugAPI(context, next) {
    // Display a UI API activity report
    if (settings.debug) {
        server.log("API received a request at " + time() + ": " + context.req.method.toupper() + " @ " + context.req.path.tolower());
        if (context.req.rawbody.len() > 0) server.log("Request body: " + context.req.rawbody.tolower());
    }
    
    // Invoke the next middleware
    next();
}

// ********** RUNTIME START **********

// Load up the crash reporter
#import "~/Dropbox/Programming/Imp/codes/slack.nut"

// If you are NOT using Squinter or a similar tool, comment out the following line...
#import "~/Dropbox/Programming/Imp/Codes/homeweather.nut"
// ...and uncomment and fill in these line:
// const APP_CODE = "YOUR_APP_UUID";
// forecaster = DarkSky("YOUR_API_KEY");
// locator = Location("YOUR_API_KEY");

// Set 'forecaster' for UK use
forecaster.setUnits("uk");
forecaster.setLanguage("en");

// Register the function to call when the device asks for a forecast
// Once this request has been successfully processed, the agent will
// automatically request updates every 15 minutes
device.on("homeweather.get.forecast", deviceIsReady);

// Manage app settings
settings = server.load();

if (settings.len() == 0) {
    // No settings saved so set the defaults
    appLog("First run - applying default settings");
    initialiseSettings();
} else {
    if (!("debug" in settings)) {
        settings.debug <- false;
        server.save(settings);
    }
}

// Set up the UI API
api = Rocky();
api.use(debugAPI);

// Set up UI access security: HTTPS only
api.authorize(function(context) {
    // Mandate HTTPS connections
    if (context.getHeader("x-forwarded-proto") != "https") return false;
    return true;
});

api.onUnauthorized(function(context) {
    // Incorrect level of access security
    context.send(401, "Insecure access forbidden");
});

// GET to root: just return the UI HTML
api.get("/", function(context) {
    context.send(200, format(HTML_STRING, http.agenturl()));
});

// GET to /dimmer: return the dimmer status
api.get("/dimmer", function(context) {
    local data = {};
    data.enabled <- settings.offatnight;
    data.dimstart <- settings.dimstart;
    data.dimend <- settings.dimend;
    data.debug <- settings.debug;
    data.state <- device.isconnected();

    if (savedData != null) {
        data.temp <- format("%.1f", savedData.temp.tofloat());
        data.outlook <- savedData.cast;
    } else {
        data.error <- "Forecast not yet available";
    }

    context.send(200, http.jsonencode(data));
});

// POST to /dimmer : Apply a setting update
api.post("/dimmer", function(context) {
    local data;

    try {
        data = http.jsondecode(context.req.rawbody);
    } catch (err) {
        appError(err);
        context.send(400, "Bad data posted");
        return;
    }

    local end = null;
    local start = null;
    local state = null;

    if ("dimstart" in data) start = data.dimstart.tointeger();
    if ("dimend" in data) end = data.dimend.tointeger();

    if ("enabled" in data) {
        // Activate or deactivate the nighttime dimmer
        state = data.enabled;
        settings.offatnight = state;
        device.send("homeweather.set.offatnight", state);
        appLog(state ? "Nighttime dimmer enabled" : "Nighttime dimmer disabled");
    }

    if ("advance" in data) {
        // Advance is only relevant if we are using the dimmer as otherwise
        // the LEDs are always turned on
        if (settings.offatnight) {
            device.send("homeweather.set.advance", true);
            appLog("Timer advanced");
            context.send(200, "Timer advanced");
            return;
        }
    }

    if (start == null && end == null && state == null) {
        // No data changed or incorrect fields used
        context.send(400, "Bad data posted");
    } else {
        if (end != null && start != null) {
            if (start < 0) start = 0;
            if (start > 23) start = 23;
            if (end > 23) end = 23;
            if (end < 0) end = 0;

            if (end == start) {
                device.send("homeweather.set.offatnight", false);
                settings.offatnight = false;
                if (start < 23) {
                    end = start + 1;
                } else {
                    start = 22;
                    end = 23;
                }
            }

            // Send the dimmer timer details to the device...
            device.send("homeweather.set.dim.start", start);
            device.send("homeweather.set.dim.end", end);

            // ... and record them here
            settings.dimstart = start;
            settings.dimend = end;
            appLog("Setting nighttime dimmer start to " + start + ", end to " + end);
        }

        context.send(202, "Nighttime dimming setting(s) applied");

        server.save(settings);
    }
});

// POST to /debug : set the debugging mode
api.post("/debug", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("debug" in data) {
            appLog(data.debug ? "Debug enabled" : "Debug disabled");
            device.send("homeweather.set.debug", data.debug);
            settings.debug = data.debug;
            server.save(settings);
        }
    } catch (err) {
        appError(err);
        context.send(400, "Bad data posted");
        return;
    }

    context.send(200, (settings.debug ? "Debug on" : "Debug off"));
});

// POST to /reset : reset the device
api.post("/reset", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("reset" in data) {
            if (data.reset) {
                // Perform the reset
                appLog("Resetting Weather Station");
                initialiseSettings();

                // Update the device with default settings
                device.send("homeweather.set.offatnight", false);
                device.send("homeweather.set.dim.start", settings.dimstart);
                device.send("homeweather.set.dim.end", settings.dimend);
                device.send("homeweather.set.debug", false);
            }
        }
    } catch (err) {
        appError(err);
        context.send(400, "Bad data posted");
        return;
    }

    context.send(200, (settings.debug ? "Debug on" : "Debug off"));
});

// GET at /controller/info returns app UUID
api.get("/controller/info", function(context) {
    local info = { "appcode": APP_CODE,
                   "watchsupported": "true" };
    context.send(200, http.jsonencode(info));
});

// GET at /controller/state returns app UUID
api.get("/controller/state", function(context) {
    local data = device.isconnected() ? "1" : "0"
    context.send(200, data);
});

// In 'RESTART_TIMEOUT' seconds' time, check if the device has not synced (as far as
// the agent knows) but is connected, ie. we have probably experienced an unexpected
// agent restart. If so, do a location lookup as if asked by a newly starting device
agentRestartTimer = imp.wakeup(RESTART_TIMEOUT, function() {
    agentRestartTimer = null;
    if (!syncFlag && device.isconnected()) {
        // Device is online so call 'deviceIsReady()'
        appLog("Recommencing forecasting due to agent restart");
        deviceIsReady(true);
    }
    // Otherwise device is not online, so the agent does nothing but wait for it to come back
});
