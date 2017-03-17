// Home Weather - wall-mount weather Station
// Copyright Tony Smith, 2015-2017

#require "DarkSky.class.nut:1.0.1"
#require "BuildAPIAgent.class.nut:1.1.1"
#require "Rocky.class.nut:2.0.0"

// CONSTANTS
const FORECAST_REFRESH = 900;
const HTML_STRING = @"<!DOCTYPE html><html lang='en-US'><meta charset='UTF-8'>
<html>
  <head>
    <title>Home Weather Station Control</title>
    <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
    <link href='//fonts.googleapis.com/css?family=Abel' rel='stylesheet'>
    <link href='//fonts.googleapis.com/css?family=Oswald' rel='stylesheet'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <style>
      .center { margin-left: auto; margin-right: auto; margin-bottom: auto; margin-top: auto; }
      body {background-color: dimGrey;}
      p {color: white; font-family: Abel}
      h2 {color: white; font-family: Abel; font-weight:bold}
      h4 {color: white; font-family: Abel}
      td {color: white; font-family: Abel}
    </style>
  </head>
  <body>
    <div class='container' style='padding: 20px'>
      <div class='container' style='border: 2px solid white'>
        <h2 class='text-center'>Home Weather Station Control <span></span><br>&nbsp;</h2>
        <div class='current-status'>
          <h4 class='temp-status' align='center'>Current Temperature: <span></span>&deg;C&nbsp;</h4>
          <h4 class='outlook-status' align='center'>Weather Outlook: <span></span></h4>
          <p align='center'>Forecast updates automatically every two minutes</p>
          <p class='error-message' align='center'><i><span></span></i></p>
        </div>
        <br>
        <hr>
        <div class='controls' align='center'>
          <form id='name-form'>
            <div class='update-fields'>
              <table width='200'>
                <tr>
                  <td align='right' width='145'>Night Mode Start Time</td>
                  <td  align='right' width='46'><input type='text' id='dimmerstart' min='0' max='22' style='width:40px;color:CornflowerBlue'></input></td>
                </tr>
                <tr>
                  <td align='right'>Night Mode End Time</td>
                  <td align='right'><input type='text' id='dimmerend' min='1' max='23' style='width:40px;color:CornflowerBlue'></input></td>
                </tr>
              </table>
              <p>&nbsp;</p>
            </div>
            <div class='update-button' style='color:dimGrey;font-family:Abel'>
              <button type='submit' id='dimmer-button' style='height:32px;width:200px'>Set Night Mode Times</button><br>&nbsp;
            </div>
            <div class='enable-button' style='color:dimGrey;font-family:Abel'>
              <button type='submit' id='dimmer-action'style='height:32px;width:200px'>Enable Night Mode</button>
            </div>
            <hr>
            <div class='debug-checkbox' style='color:white;font-family:Abel'>
              <small><input type='checkbox' name='debug' id='debug' value='debug'> Debug Mode</small>
            </div>
          </form>
        </div>
        <hr>
        <p class='text-center' style='font-family:Oswald'><small>Home Weather Station Control copyright &copy; Tony Smith, 2014-17</small><br>&nbsp;<br><img src='https://smittytone.github.io/rassilon.png' width='32' height='32'></p>
      </div>
    </div>
    <script src='https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js'></script>
    <script>
        // Variables
        var dimstate = true;
        var agenturl = '%s';

        // Get initial readout data
        getState(updateReadout);

        // Set object click actions
        $('.update-button button').click(setDimTime);
        $('.enable-button button').click(setDimEnable);
        $('#debug').click(setdebug);

        function setDimTime(e){
            // Set the night mode duration
            e.preventDefault();
            var start = document.getElementById('dimmerstart').value;
            var end = document.getElementById('dimmerend').value;
            setTime(start, end);
            $('#name-form').trigger('reset');
        }

        function setDimEnable(e){
            // Enable/disable night mode
            e.preventDefault();
            state = !state;
            setState(state);
            $('#name-form').trigger('reset');
        }

        function updateReadout(data) {
            // Update the UI with data from the device
            if (data.error) {
                $('.error-message span').text(data.error);
            } else {
                // Set the weather forecast data
                $('.temp-status span').text(data.temp);
                $('.outlook-status span').text(data.outlook);
            }

            // Set the 'enable' button text
            var bs = 'Disable Night Mode';
            dimstate = true;
            if (data.enabled == false) {
                bs = 'Enable Night Mode';
                dimstate = false;
            }

            $('#dimmer-action').text(bs);

            // Set the night mode times
            document.getElementById('dimmerstart').value = data.dimstart;
            document.getElementById('dimmerend').value = data.dimend;

            $('.text-center span').text(data.vers);
            document.getElementById('debug').checked = data.debug;

            // Clear the error readout
            $('.error-message span').text(' ');

            // Auto-reload data in 120 seconds
            setTimeout(function() {
                getState(updateReadout);
            }, 120000);
        }

        function getState(callback) {
            // Get the data from the device
            $.ajax({
                url : agenturl + '/dimmer',
                type: 'GET',
                success : function(response) {
                    response = JSON.parse(response);
                    if (callback && ('temp' in response)) {
                        callback(response);
                    }
                }
            });
        }

        function setTime(start, end) {
            // Set the night mode times
            $.ajax({
                url : agenturl + '/dimmer',
                type: 'POST',
                data: JSON.stringify({ 'dimstart' : start, 'dimend' : end }),
                success : function(response) {
                    getState(updateReadout);
                }
            });
        }

        function setState(aState) {
            // Enable/disable night mode
            $.ajax({
                url : agenturl + '/dimmer',
                type: 'POST',
                data: JSON.stringify({ 'enabled' : aState }),
                success : function(response) {
                    getState(updateReadout);
                }
            });
        }

        function setdebug() {
            // Tell the device to enter or leave debug mode
            $.ajax({
                url : agenturl + '/debug',
                type: 'POST',
                data: JSON.stringify({ 'debug' : document.getElementById('debug').checked })
            });
        }
    </script>
  </body>
</html>";

// GLOBALS
local request = null;
local forecaster = null;
local nextForecastTimer = null;
local agentRestartTimer = null;
local build = null;
local apiKey = null;
local api = null;
local savedData = null;

local myLongitude = -0.147118;
local myLatitude = 51.592907;
local appVersion = "2.2";
local appName = "HomeWeather";
local debug = true;
local firstRun = false;
local syncFlag = false;
local settings = {};

// WEATHER FUNCTIONS

function getForecast() {
    // Request the weather data from Forecast.io asynchronously
    if (debug) server.log("Requesting a forecast");
    forecaster.forecastRequest(myLongitude, myLatitude, forecastCallback);
}

function forecastCallback(err, data) {
    // Decode the JSON-format data from forecast.io (error thrown if invalid)
    if (debug) {
        if (err) server.error(err);
        if (data) server.log("Weather forecast data received from DarkSky");
    }

    if (data) {
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

                local initial = sendData.cast.slice(0, 1);
                sendData.cast = initial.toupper() + sendData.cast.slice(1);

                // Send the icon name to the device
                sendData.icon <- item.icon;
                sendData.temp <- item.apparentTemperature;
                sendData.rain <- item.precipProbability;
                device.send("homeweather.show.forecast", sendData);
                savedData = sendData;
                if (debug) server.log("Forecast: " + sendData.cast + ". Temp: " + sendData.temp + "\'C. Chance of rain: " + (sendData.rain * 100) + "%");
            }
        }

        if (debug && "callCount" in data) server.log("Current Forecast API call tally: " + data.callCount + "/1000");
    }

    // Get the next forecast in an 'FORECAST_REFRESH' minutes' time
    if (nextForecastTimer) imp.cancelwakeup(nextForecastTimer);
    nextForecastTimer = imp.wakeup(FORECAST_REFRESH, getForecast);
}

function deviceReady(dummy) {
    // This is called by the device via agent.send() when it starts
    // or by the agent itself after an agent migration
    if (agentRestartTimer) imp.cancelwakeup(agentRestartTimer);
    agentRestartTimer = null;
    syncFlag = true;
    device.send("homeweather.set.debug", debug);
    getForecast();
}

// PROGRAM START

// You will need to uncomment the following lines...
// forecaster = DarkSky("<YOUR_API_KEY>");
// build = BuildAPIAgent("<YOUR_API_KEY>");
// apiKey = "<YOUR_SELF-GENERATED_UUID_(OPTIONAL)>"

// ...and comment out the following line
#import "~/Dropbox/Programming/Imp/Codes/homeweather.nut"

// Set 'forecaster' for UK use
forecaster.setUnits("uk");

// Register the function to call when the device asks for a forecast
// Once this request has been successfully processed, the agent will
// automatically request updates every 15 minutes
device.on("homeweather.get.forecast", deviceReady);

// Manage app settings
// Clear app settings if required
if (firstRun) server.save({});

settings = server.load();
if (settings.len() == 0) {
    // No settings saved so set the defaults
    settings.dimstart <- 21;
    settings.dimend <- 6;
    settings.offatnight <- true;
    settings.debug <- false;

    // Save the settings immediately
    local result = server.save(settings);
    if (result != 0) server.error("Settings could not be saved");
}

// Fix for added settings fields
if ("debug" in settings) {
    debug = settings.debug;
} else {
    settings.debug <- debug;
}

// Set up the API
api = Rocky();

api.get("/", function(context) {
    // Root request: just return standard HTML string
    context.send(200, format(HTML_STRING, http.agenturl()));
});

api.get("/dimmer", function(context) {
    // Handle request for night dimmer status
    local data = {};
    data.enabled <- settings.offatnight;
    data.dimstart <- settings.dimstart;
    data.dimend <- settings.dimend;
    data.debug <- settings.debug;
    data.vers <- appVersion.slice(0, 3);

    if (savedData != null) {
        data.temp <- savedData.temp;
        data.outlook <- savedData.cast;
    } else {
        data.error <- "Forecast not yet available - try again soon";
    }

    data = http.jsonencode(data);
    context.send(200, data);
});

api.post("/dimmer", function(context) {
    // Apply setting for data from /dimmer endpoint
    local data;

    try {
        data = http.jsondecode(context.req.rawbody);
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted");
        return;
    }

    local end = null;
    local start = null;
    local state = null;

    if ("dimstart" in data) start = data.dimstart.tointeger();
    if ("dimend" in data) end = data.dimend.tointeger();
    if ("enabled" in data) {
        state = data.enabled;
        settings.offatnight = state;
        device.send("homeweather.set.offatnight", state);
        if (debug) server.log(state ? "Dimmer enabled" : "Dimmer disabled");
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

            device.send("homeweather.set.dim.start", start);
            device.send("homeweather.set.dim.end", end);

            settings.dimstart = start;
            settings.dimend = end;
            if (debug) server.log("Setting dimmer start to " + start + ", end to " + end);
        }

        context.send(202, "Night dimming setting(s) applied");

        local result = server.save(settings);
        if (result != 0) server.error("Settings could not be saved");
    }
});

api.post("/debug", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("debug" in data) {
            debug = data.debug;
            if (debug) {
                server.log("Debug enabled");
            } else {
                server.log("Debug disabled");
            }

            device.send("homeweather.set.debug", debug);
            settings.debug = debug;
            local result = server.save(settings);
            if (result != 0) server.error("Could not save settings (code: " + result + ")");
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted");
        return;
    }

    context.send(200, (debug ? "Debug on" : "Debug off"));
});

// Comment out the following 16 lines if you are not using the Build API integration
build.getModelName(imp.configparams.deviceid, function(err, data) {
    if (err) {
        server.error(err);
    } else {
        appName = data;
        build.getLatestBuildNumber(appName, function(err, data) {
            if (err) {
                server.error(err);
            } else {
                appVersion = appVersion + "." + data;
            }
        }.bindenv(this));
    }
}.bindenv(this));

if (debug) server.log("Starting \"" + appName + "\" build " + appVersion);

// In five minutes' time, check if the device has not synced (as far as
// the agent knows) but is connected, ie. we have probably experienced
// an unexpected agent restart. If so, do a location lookup as if asked
// by a newly starting device
agentRestartTimer = imp.wakeup(300, function() {
    agentRestartTimer = null;
    if (!syncFlag) {
        if (device.isconnected()) {
            if (debug) server.log("Restarting forecasting due to agent restart");
            deviceReady(true);
        }
    }
});
