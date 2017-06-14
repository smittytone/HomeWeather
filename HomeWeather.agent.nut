// Home Weather - wall-mount weather Station
// Copyright Tony Smith, 2015-2017

#require "DarkSky.class.nut:1.0.1"
#require "Rocky.class.nut:2.0.0"

// CONSTANTS
const FORECAST_REFRESH = 900;
const HTML_STRING = @"<!DOCTYPE html><html lang='en-US'><meta charset='UTF-8'>
<html>
    <head>
        <title>Home Weather Station Control</title>
        <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
        <link href='https://fonts.googleapis.com/css?family=Abel' rel='stylesheet'>
        <link href='https://fonts.googleapis.com/css?family=Oswald' rel='stylesheet'>
        <link rel='apple-touch-icon' href='https://smittytone.github.io/images/ati-wstation.png'>
        <link rel='shortcut icon' href='https://smittytone.github.io/images/ico-wstation.ico'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <style>
            .center { margin-left: auto; margin-right: auto; margin-bottom: auto; margin-top: auto; }
            body {background-color: dimGrey;}
            p {color: white; font-family: Abel}
            h2 {color: white; font-family: Abel; font-weight:bold}
            h4 {color: white; font-family: Abel}
            td {color: white; font-family: Abel}
            p.showhide {cursor: pointer}
        </style>
    </head>
    <body>
        <div class='container' style='padding: 20px'>
            <div style='border: 2px solid white'>
                <h2 class='text-center'>Home Weather Station Control<br>&nbsp;</h2>
                <table width='100%%'>
                    <tr>
                        <td width='20%%'>&nbsp;</td>
                        <td width='60%%'>
                            <div class='current-status'>
                                <h4 class='temp-status' align='center'>Current Temperature: <span></span>&deg;C&nbsp;</h4>
                                <h4 class='outlook-status' align='center'>Weather Outlook: <span></span></h4>
                                <p align='center'>Forecast updates automatically every two minutes</p>
                                <p class='error-message' align='center'><i><span></span></i></p>
                            </div>
                            <br>
                            <hr>
                            <div class='controls' align='center'>
                                <div class='update-fields'>
                                    <table width='100%%'>
                                        <tr>
                                            <td align='center' colspan='2'><h4 class='dimstatus'><span>Night Mode Enabled</span></h4><br></td>
                                        </tr>
                                        <tr>
                                            <td align='right' width='58%%'>Night Mode Start Time (hour)&nbsp;</td>
                                            <td align='left' width='42%%'>&nbsp;<input type='text' id='dimmerstart' min='0' max='22' style='width:40px;color:CornflowerBlue'></input></td>
                                        </tr>
                                        <tr>
                                            <td align='right'>Night Mode End Time (hour)&nbsp;</td>
                                            <td align='left'>&nbsp;<input type='text' id='dimmerend' min='1' max='23' style='width:40px;color:CornflowerBlue'></input></td>
                                        </tr>
                                        <tr>
                                            <td align='center' colspan='2'><small>Set the on and off times in the 24-hour clock format</small></td>
                                        </tr>
                                    </table>
                                    <p>&nbsp;</p>
                                </div>
                                <div class='update-button' style='color:black;font-family:Abel'>
                                    <button type='submit' id='dimmer-button' style='height:32px;width:200px'>Set Night Mode Times</button><br>&nbsp;
                                </div>
                                <div class='enable-button' style='color:black;font-family:Abel'>
                                    <button type='submit' id='dimmer-action' style='height:32px;width:200px'>Disable Night Mode</button>
                                </div>
                                <hr>
                                <div class='advancedsettings'>
                                    <p class='showhide' align='center'>Show Advanced Settings</p>
                                    <div class='advanced' align='center'>
                                        <div class='debug-checkbox' style='color:white;font-family:Abel'>
                                            <small><input type='checkbox' name='debug' id='debug' value='debug'> Debug Mode</small><br>&nbsp;
                                        </div>
                                        <div class='reset-button' style='color:black;font-family:Abel'>
                                            <button type='submit' id='resett-button' style='height:32px;width:200px'>Reset Station</button>
                                        </div>
                                    </div>
                                </div>
                            </div>
                            <hr>
                            <p class='text-center' style='font-family:Oswald'><small>Home Weather Station Control copyright &copy; Tony Smith, 2014-17</small><br>&nbsp;<br><a href='https://github.com/smittytone/HomeWeather'><img src='https://smittytone.github.io/images/rassilon.png' width='32' height='32'></a></p>
                        </td>
                        <td width='20%%'>&nbsp;</td>
                    </tr>
                </table>
            </div>
        </div>
    <script src='https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js'></script>
    <script>
        $('.advanced').hide();

        // Variables
        var dimstate = true;
        var agenturl = '%s';

        // Get initial readout data
        getState(updateReadout);

        // Set object click actions
        $('.update-button button').click(setDimTime);
        $('.enable-button button').click(setDimEnable);
        $('.reset-button button').click(doReset);
        $('#debug').click(setDebug);
        $('.showhide').click(function(){
            $('.advanced').toggle();
            var isVis = $('.advanced').is(':visible');
            $('.showhide').text(isVis ? 'Hide Advanced Settings' : 'Show Advanced Settings');
        });

        function setDimTime(e){
            // Set the night mode duration
            e.preventDefault();
            var start = document.getElementById('dimmerstart').value;
            var end = document.getElementById('dimmerend').value;
            setTime(start, end);
        }

        function setDimEnable(e){
            // Enable/disable night mode
            e.preventDefault();
            dimstate = !dimstate;
            setDimUI(dimstate);
            setState(dimstate);
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
            dimstate = data.enabled;
            setDimUI(dimstate);

            // Set the night mode times
            document.getElementById('dimmerstart').value = data.dimstart;
            document.getElementById('dimmerend').value = data.dimend;

            // Set the debug mode advanced option
            document.getElementById('debug').checked = data.debug;

            // Clear the error readout
            $('.error-message span').text(' ');

            // Auto-reload data in 120 seconds
            setTimeout(function() {
                getState(updateReadout);
            }, 120000);
        }

        function setDimUI(state) {
            $('#dimmer-action').text(state ? 'Disable Night Mode' : 'Enable Night Mode');
            $('.dimstatus span').text(state ? 'Night Mode Enabled' : 'Night Mode Disabled');
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

        function setDebug() {
            // Tell the device to enter or leave debug mode
            $.ajax({
                url : agenturl + '/debug',
                type: 'POST',
                data: JSON.stringify({ 'debug' : document.getElementById('debug').checked })
            });
        }

        function doReset() {
            // Tell the device to reset itself
            $.ajax({
                url : agenturl + '/reset',
                type: 'POST',
                data: JSON.stringify({ 'reset' : true }),
                success: function(response) {
                    getState(updateReadout);
                }
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
local apiKey = null;
local api = null;
local savedData = null;

local myLongitude = -0.147118;
local myLatitude = 51.592907;
local debug = true;
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
                if (debug) server.log("Forecast: " + sendData.cast + ". Temperature: " + sendData.temp + "C. Chance of rain: " + (sendData.rain * 100) + "%");
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

function resetSettings() {
    // Reset the settings to the defaults
    // First clear the saved data in case the settings keys have changed
    server.save({});

    // Create a new settings table
    settings = {};
    settings.dimstart <- 22;
    settings.dimend <- 7;
    settings.offatnight <- false;
    settings.debug <- false;
    debug = false;

    // Save the new table
    local result = server.save(settings);
    if (result != 0) server.error("Settings could not be saved");
}

// PROGRAM START

// You will need to uncomment the following lines...
// forecaster = DarkSky("<YOUR_API_KEY>");
// apiKey = "<YOUR_SELF-GENERATED_UUID_(OPTIONAL)>"

// ...and comment out the following line if you are not using Squinter
#import "~/Dropbox/Programming/Imp/Codes/homeweather.nut"

// Set 'forecaster' for UK use
forecaster.setUnits("uk");

// Register the function to call when the device asks for a forecast
// Once this request has been successfully processed, the agent will
// automatically request updates every 15 minutes
device.on("homeweather.get.forecast", deviceReady);

// Manage app settings
settings = server.load();

if (settings.len() == 0) {
    // No settings saved so set the defaults
    server.log("First run - applying default settings");
    resetSettings();
}

// Set up the UI API
api = Rocky();

api.get("/", function(context) {
    // Root request: just return the UI HTML
    context.send(200, format(HTML_STRING, http.agenturl()));
});

api.get("/dimmer", function(context) {
    // Handle request for night dimmer status
    local data = {};
    data.enabled <- settings.offatnight;
    data.dimstart <- settings.dimstart;
    data.dimend <- settings.dimend;
    data.debug <- settings.debug;

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
        if (debug) server.log(state ? "Nighttime dimmer enabled" : "Nighttime dimmer disabled");
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
            if (debug) server.log("Setting nighttime dimmer start to " + start + ", end to " + end);
        }

        context.send(202, "Nighttime dimming setting(s) applied");

        local result = server.save(settings);
        if (result != 0) server.error("Could not save settings (code: " + result + ")");
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

api.post("/reset", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("reset" in data) {
            if (data.reset) {
                // Perform the reset
                server.log("Resetting Weather Station");
                resetSettings();

                // Update the device
                device.send("homeweather.set.offatnight", false);
                device.send("homeweather.set.dim.start", settings.dimstart);
                device.send("homeweather.set.dim.end", settings.dimend);
                device.send("homeweather.set.debug", false);
            }
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted");
        return;
    }

    context.send(200, (debug ? "Debug on" : "Debug off"));
});

// In five minutes' time, check if the device has not synced (as far as
// the agent knows) but is connected, ie. we have probably experienced
// an unexpected agent restart. If so, do a location lookup as if asked
// by a newly starting device
agentRestartTimer = imp.wakeup(300, function() {
    agentRestartTimer = null;
    if (!syncFlag) {
        if (device.isconnected()) {
            if (debug) server.log("Recommencing forecasting due to agent restart");
            deviceReady(true);
        }
    }
});