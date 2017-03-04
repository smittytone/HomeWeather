#require "DarkSky.class.nut:1.0.1"
#require "BuildAPIAgent.class.nut:1.1.1"
#require "Rocky.class.nut:2.0.0"

// CONSTANTS
const forecastRefreshTime = 900;

const htmlString = @"
    <!DOCTYPE html>
    <html>
        <head>
            <title>Home Weather Station Control</title>
            <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
            <meta name='viewport' content='width=device-width, initial-scale=1.0'>
            <style>
                .center { margin-left: auto; margin-right: auto; margin-bottom: auto; margin-top: auto; }
            </style>
        </head>
        <body>
            <div class='container' style='padding: 20px'>
            <div class='container' style='border: 2px solid gray'>
                <h2 class='text-center'>Home Weather Station Control</h2>
                <div class='current-status'>
                    <h4 class='temp-status'>Temperature: <span></span>&deg;C&nbsp;</h4><h4 class='outlook-status'>Outlook: <span></span></h4>
                </div>
                <br>
                <div class='controls'>
                    <form id='name-form'>
                        <div class='update-fields'>
                            <label>Night Dimmer Start Time:</label>&nbsp;<input id='dimmerstart' style='width:40px'></input><br>
                            <label>Night Dimmer End Time:</label>&nbsp;&nbsp;<input id='dimmerend' style='width:40px'></input><br>&nbsp;
                        </div>
                        <div class='update-button'>
                            <button type='submit' id='dimmer-button' style='height:24px;width:200px'>Submit Dimmer Time</button><br>&nbsp;
                        </div>
                        <div class='enable-button'>
                            <button type='submit' id='dimmer-action'style='height:24px;width:200px'>Enable Night Dimmer</button>
                        </div>
                    </form>
                </div> <!-- controls -->
                &nbsp;<br>&nbsp;
            </div>  <!-- container -->
            </div>
            <script src='https://ajax.googleapis.com/ajax/libs/jquery/3.1.0/jquery.min.js'></script>
            <script>
                var state = true;
                var agenturl = '%s';
                getState(updateReadout);
                $('.update-button button').on('click', setStateTime);
                $('.enable-button button').on('click', setStateEnable);

                function setStateTime(e){
                    e.preventDefault();
                    var start = document.getElementById('dimmerstart').value;
                    var end = document.getElementById('dimmerend').value;
                    setTime(start, end);
                    $('#name-form').trigger('reset');
                }

                function setStateEnable(e){
                    e.preventDefault();
                    state = !state;
                    setState(state);
                    $('#name-form').trigger('reset');
                }

                function updateReadout(data) {
                    var bs = 'Disable Night Dimmer';
                    state = true;
                    if (data.enabled == false) {
                        bs = 'Enable Night Dimmer';
                        state = false;
                    }

                    $('#dimmer-action').text(bs);
                    document.getElementById('dimmerstart').value = data.dimstart;
                    document.getElementById('dimmerend').value = data.dimend;

                    $('.temp-status span').text(data.temp);
                    $('.outlook-status span').text(data.outlook);

                    setTimeout(function() {
                        getState(updateReadout);
                    }, 120000);
                }

                function getState(callback) {
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
                    $.ajax({
                        url : agenturl + '/dimmer',
                        type: 'POST',
                        data: JSON.stringify({ 'dimstart' : start,
                                               'dimend' : end }),
                        success : function(response) {
                            getState(updateReadout);
                        }
                    });
                }

                function setState(aState) {
                    $.ajax({
                        url : agenturl + '/dimmer',
                        type: 'POST',
                        data: JSON.stringify({ 'enabled' : aState }),
                        success : function(response) {
                            console.log(response);
                            getState(updateReadout);
                        }
                    });
                }


            </script>
        </body>
    </html>
";

// GLOBALS
local request = null;
local forecaster = null;
local nextForecastTimer = null;
local agentRestartTimer = null;
local build = null;
local apiKey = null;
local api = null;
local homeData = null;

local myLongitude = -0.147118;
local myLatitude = 51.592907;
local deviceSyncFlag = false;
local appVersion = "2.2";
local appName = "HomeWeather";
local debug = true;
local firstRun = false;
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
        if (data) server.log("Weather forecast data received from forecast.io");
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

                // Send the icon name to the device
                sendData.icon <- item.icon;
                sendData.temp <- item.apparentTemperature;
                sendData.rain <- item.precipProbability;
                device.send("homeweather.show.forecast", sendData);
                homeData = sendData;

                if (debug) server.log("Forecast: " + sendData.cast + ". Temp: " + sendData.temp + "\'C. Chance of rain: " + (sendData.rain * 100) + "%");
            }
        }

        if (debug && "callCount" in data) server.log("Current Forecast API call tally: " + data.callCount + "/1000");
    }

    // Get the next forecast in an 'forecastRefreshTime' minutes' time
    if (nextForecastTimer) imp.cancelwakeup(nextForecastTimer);
    nextForecastTimer = imp.wakeup(forecastRefreshTime, getForecast);
}

function deviceReady(dummy) {
    // This is called by the device via agent.send() when it starts
    // or by the agent itself after an agent migration
    if (agentRestartTimer) imp.cancelwakeup(agentRestartTimer);
    agentRestartTimer = null;
    deviceSyncFlag = true;
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
if (firstRun != true) settings = server.load();
if (settings.len() == 0) {
    // No settings saved so set the defaults
    settings.dimstart <- 21;
    settings.dimend <- 6;
    settings.offatnight <- true;

    // Save the settings immediately
    local result = server.save(settings);
    if (result != 0 && debug) server.error("Settings could not be saved");
}

// Register the API handler
// http.onrequest(httpHandler);
api = Rocky();

// Set up the app's API
api.get("/", function(context) {
    // Root request: just return standard HTML string
    context.send(200, format(htmlString, http.agenturl()));
});

api.get("/dimmer", function(context) {
    // Handle request for night dimmer status
    local data = {};
    data.enabled <- settings.offatnight;
    data.dimstart <- settings.dimstart;
    data.dimend <- settings.dimend;

    if (homeData != null) {
        data.temp <- homeData.temp;
        data.outlook <- homeData.cast;
    } else {
        data.temp <- "??";
        data.outlook <- "unknown";
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
                settings.offatnight = state;
            } else {
                device.send("homeweather.set.dim.start", start);
                device.send("homeweather.set.dim.end", end);
            }

            settings.dimstart = start;
            settings.dimend = end;
        }

        context.send(202, "Night dimming setting(s) applied");

        local result = server.save(settings);
        if (result != 0 && debug) server.error("Settings could not be saved");
    }
});

// Comment out the following three lines if you are not using the Build API integration
appName = build.getModelName(imp.configparams.deviceid);
appVersion = build.getLatestBuildNumber(appName);
if (debug) server.log("Starting \"" + appName + "\" build " + appVersion);

// In five minutes' time, check if the device has not synced (as far as
// the agent knows) but is connected, ie. we have probably experienced
// an unexpected agent restart. If so, do a location lookup as if asked
// by a newly starting device
agentRestartTimer = imp.wakeup(300, function() {
    agentRestartTimer = null;
    if (!deviceSyncFlag) {
        if (device.isconnected()) {
            if (debug) server.log("Restarting forecasting due to agent restart");
            deviceReady(true);
        }
    }
});
