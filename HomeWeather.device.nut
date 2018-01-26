// Home Weather - wall-mount weather Station
// Copyright Tony Smith, 2015-2018

// IMPORTS
#import "../generic/utilities.nut"
#import "../ht16k33segment/ht16k33segment.class.nut"
#import "../ht16k33matrix/ht16k33matrix.class.nut"
#import "../ht16k33bargraph/ht16k33bargraph.class.nut"

// EARLY-RUN CODE
// Set the imp disconnection policy
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

// CONSTANTS
const LED_OFF = 0;
const LED_RED = 1;
const LED_AMBER = 2;
const LED_GREEN = 3;
const DISPLAY_ON = 0xFF;
const DISPLAY_OFF = 0x00;
const RECONNECT_TIMEOUT = 30;
const DISCONNECT_TIMEOUT = 600;
const SWITCH_TIME = 2;

// GLOBALS
local matrix = null;
local segment = null;
local bar = null;
local savedForecast = null;
local now = null;
local hbTimer = null;
local reconnectTimer = null;
local nightTime = 21;
local dayTime = 6;
local displayState = DISPLAY_ON;
local nightFlag = true;
local advanceFlag = false;
local timeFlag = true;
local discFlag = false;
local discMessage = "";
local debug = true;
local iconset = {};

// FUNCTIONS
function heartbeat() {
    // This function runs every 'SWITCH_TIME' seconds to manage the segment LED
    hbTimer = imp.wakeup(SWITCH_TIME, heartbeat);

    now = date();
    if (utilities.bstCheck()) now.hour++;
    if (now.hour > 23) now.hour = 0;

    if (showDisplay(now.hour, now.min)) {
        // The displays should be ON
        if (displayState == DISPLAY_OFF) {
            // 'displayState' hasn't been updated so power up the LEDs
            segment.powerUp();
            matrix.powerUp();
            bar.powerUp();
            displayState = DISPLAY_ON;
            if (debug) server.log("Brightening display at " + now.hour + (now.hour < 12 ? "am" : "pm"));
        }

        // Every 'SWITCH_TIME' seconds we display the temperature,
        // alternating with the time
        // autoBrightness();
        segment.clearDisplay();

        if (!timeFlag) {
            displayTemp(savedForecast);
        } else {
            displayTime();
        }

        timeFlag = !timeFlag;
    } else {
        // The display should be OFF
        if (displayState == DISPLAY_ON) {
            // 'displayState' hasn't been updated so power down the LEDs
            segment.powerDown();
            matrix.powerDown();
            bar.powerDown();
            displayState = DISPLAY_OFF;
            if (debug) server.log("Dimming display at " + now.hour + (now.hour < 12 ? "am" : "pm"));
        }
    }
}

function showDisplay(hour, minute) {
    // Returns true if the display should be on, false otherwise - default is true / on
    // If we have auto-dimming set, we need only check whether we need to turn the display off
    local returnValue = true;
    if (nightFlag && (hour < dayTime || hour >= nightTime)) returnValue = false;
    return (advanceFlag ? !returnValue : returnValue);
}

function autoBrightness() {
    // ********** EXPERIMENTAL **********
    // 'bright' value is a 16-but unsigned value: 0 - 65535
    // Use to generate a display brightness between 0 and 15
    local l = hardware.lightlevel();
    local bright = (l.tofloat() / 65535.0) * 15;
    bright = bright.tointeger() - 4;
    if (bright < 0) bright = 0;

    segment.setBrightness(bright);
    matrix.setBrightness(bright);
    bar.setBrightness(bright);
    if (debug) server.log("Brightness set to " + bright + "(light level: " + l + ")");
}

function displayDisconnected() {
    // Put 'dISC' onto the segment display to indicate status
    segment.writeChar(0, 0x5E, false);
    segment.writeChar(1, 0x06, false);
    segment.writeChar(3, 0x6D, false);
    segment.writeChar(4, 0x39, false);
    segment.updateDisplay();
}

function displayTemp(data) {
    // Disconnected? Indicate on the display and bail
    if (discFlag) {
        displayDisconnected();
        return;
    }

    // No data to display or the display should be off? Bail
    if (data == null) return;

    // Temperature is in Celsius (see agent code)
    local minusFlag = false;
    local temperature = data.temp.tofloat();
    if (temperature < 0.1 && temperature > -0.1) temperature = 0.0;
    local num = format("%.2f", temperature).tofloat();
    if (num > 99.99) num = 99.99;
    if (num < 0) minusFlag = true;
    num = num * 100;

    if (minusFlag) {
        // Write a minus sign at first digit
        segment.writeChar(0, 0x40);
        num = num * -1;
        if (num > 999) {
            // Temp is -10 or less so show the two digits and ignore the decimal
            segment.writeNumber(1, (num / 1000).tointeger());
            num = num - ((num / 1000).tointeger() * 1000);
            if (num > 99) {
                segment.writeNumber(3, (num / 100).tointeger());
            } else {
                segment.writeNumber(3, 0, false);
            }
        } else {
            // Temp is below than 0 but more than -10, eg. -9.9
            // So add a decimal point after the first digit
            if (num > 99) {
                segment.writeNumber(1, (num / 100).tointeger(), true);
                num = num - ((num / 100).tointeger() * 100);
            } else {
                segment.writeNumber(1, 0, true);
            }

            if (num > 9) {
                segment.writeNumber(3, (num / 10).tointeger());
            } else {
                // This prevents eg. '-2. C'
                segment.writeNumber(3, 0);
            }
        }
    } else {
        if (num == 0) {
            // Temp is zero
            segment.writeNumber(3, 0);
        } else {
            if (num > 999) {
                segment.writeNumber(0, (num / 1000).tointeger());
                num = num - ((num / 1000).tointeger() * 1000);
            } else {
                segment.writeNumber(0, 16);
            }

            if (num > 99) {
                segment.writeNumber(1, (num / 100).tointeger(), true);
                num = num - ((num / 100).tointeger() * 100);
            } else {
                segment.writeNumber(1, 0, true);
            }

            if (num > 9) {
                segment.writeNumber(3, (num / 10).tointeger());
            } else {
                segment.writeNumber(3, 0);
            }
        }
    }

    // Add the degree symbol and clear the colon
    segment.writeChar(4, 0x63).setColon(false).updateDisplay();
}

function displayTime() {
    local h = now.hour;
    local m = 0;

    if (h < 10) {
        segment.writeNumber(0, 16, false);
        segment.writeNumber(1, h, false);
    } else if (h > 9 && h < 20) {
        segment.writeNumber(0, 1, false)
        segment.writeNumber(1, h - 10, false);
    } else if (h > 19) {
        segment.writeNumber(0, 2, false);
        segment.writeNumber(1, h - 20, false);
    }

    if (now.min > 9) {
        h = now.min;

        while (h >= 0) {
            h = h - 10;
            ++m;
        }

        segment.writeNumber(4, (now.min - (10 * (m - 1))), false);
        segment.writeNumber(3, m - 1, false);
    } else {
        segment.writeNumber(4, now.min, false);
        segment.writeNumber(3, 0, false);
    }

    segment.setColon(true).updateDisplay();
}

function displayWeather(data) {
    // This is intended only to be called in response to data from the agent
    // It manages the matrix LED and the LED bar graph

    if (data == null) {
        // No passed in weather data? Use the last forecast
        if (savedForecast == null) return;
        data = saveForecast;
    }

    // Save the current forecast for next time, in case the function is NOT
    // triggered by the agent
    savedForecast = data;

    if (showDisplay(now.hour, now.min)) {
        // Show the rain level and the current forecast icon
        displayRain(data);
        displayIcon(data);
    }
}

function displayRain(data) {
    // Set the rain gauge
    // Should not be called if the display should be off
    bar.clear().fill((23.0 * data.rain.tofloat()), LED_AMBER).draw();
}

function displayIcon(data) {
    // Display the weather type on the matrix
    // Should not be called if the display should be off
    matrix.displayLine(data.cast);

    local icon;
	try {
    	icon = clone(iconset[data.icon]);
    } catch (error) {
    	icon = clone(iconset[none]);
    }

    // Display the weather icon
    matrix.displayIcon(icon);
}

// OFFLINE OPERATION FUNCTIONS
function discHandler(reason) {
    // Called if the server connection is broken or re-established
    // Sets 'discFlag' to true if there is no connection
    if (reason != SERVER_CONNECTED) {
        // We weren't previously disconnected, so mark us as disconnected now
        if (!discFlag) {
            discFlag = true;
            local now = date();
            discMessage = "Went offline at " + now.hour + ":" + now.min + ":" + now.sec + ". Reason: " + reason;
        }

        // Schedule an attempt to re-connect in DISCONNECT_TIMEOUT seconds
        if (reconnectTimer == null) reconnectTimer = imp.wakeup(DISCONNECT_TIMEOUT, reconnect);
    } else {
        // Back online so request a weather forecast from the agent
        if (discFlag) {
            if (debug) {
                server.log(discMessage);
                local now = date();
                server.log("Now back online at " + now.hour + ":" + now.min + ":" + now.sec);
            }

            // Get a forecast - this will also update the settings
            agent.send("homeweather.get.forecast", true);
        }

        discFlag = false;

        // Clear the reconnect timer
        if (reconnectTimer != null) {
            imp.cancelwakeup(reconnectTimer);
            reconnectTimer = null;
        }
    }
}

function reconnect() {
    // Called when necessary in order to attempt to reconnect to the server
    if (server.isconnected()) {
       // Is the unit already connected for some reason? If so trigger the 'connected' flow via 'discHandler()'
       discHandler(SERVER_CONNECTED);
    } else {
        // The clock is still disconnected, so attempt to connect
        server.connect(discHandler, RECONNECT_TIMEOUT);
    }
}

// START OF PROGRAM
// Load in generic boot message code (comment out if you're not using Squinter)
#include "../generic/bootmessage.nut"

// Register for unexpected disconnections
server.onunexpecteddisconnect(discHandler);

// Set up the matrix display
hardware.i2c89.configure(CLOCK_SPEED_400_KHZ);
matrix = HT16K33Matrix(hardware.i2c89, 0x70, true);
matrix.init(1, 3);

// Set up the segment display
segment = HT16K33Segment(hardware.i2c89, 0x72);
segment.init(16, 1, false);

// Set up the bar
bar = HT16K33Bargraph(hardware.i2c89, 0x74, true);
bar.init(1, false);

// Load weather icons
iconset.clearday <- [0x89,0x42,0x18,0xBC,0x3D,0x18,0x42,0x91];
iconset.clearnight <- [0x0,0x0,0x0,0x81,0xE7,0x7E,0x3C,0x18];
iconset.rain <- [0x8C,0x5E,0x1E,0x5F,0x3F,0x9F,0x5E,0x0C];
iconset.lightrain <- [0x8C,0x52,0x12,0x51,0x31,0x91,0x52,0xC];
iconset.snow <- [0x14,0x49,0x2A,0x1C,0x1C,0x2A,0x49,0x14];
iconset.sleet <- [0x4C,0xBE,0x5E,0xBF,0x5F,0xBF,0x5E,0xAC];
iconset.wind <- [0x28,0x28,0x28,0x28,0x28,0xAA,0xAA,0x44];
iconset.fog <- [0x55,0xAA,0x55,0xAA,0x55,0xAA,0x55,0xAA];
iconset.cloudy <- [0x0C,0x1E,0x1E,0x1F,0x1F,0x1F,0x1E,0x0C];
iconset.partlycloudy <- [0x0C,0x12,0x12,0x11,0x11,0x11,0x12,0x0C];
iconset.thunderstorm <- [0x0,0x0,0x0,0xF0,0x1C,0x7,0x0,0x0];
iconset.tornado <- [0x0,0x2,0x36,0x7D,0xDD,0x8D,0x6,0x2];
iconset.none <- [0x0,0x0,0x2,0xB9,0x9,0x6,0x0,0x0];

// Set up agent interaction
agent.on("homeweather.show.forecast", displayWeather);

agent.on("homeweather.set.dim.start", function(value) {
    nightTime = value;
    if (debug) server.log("Display off time set to " + value);
});

agent.on("homeweather.set.dim.end", function(value) {
    dayTime = value;
    if (debug) server.log("Display on time set to " + value);
});

agent.on("homeweather.set.offatnight", function(value) {
    nightFlag = value;
    if (debug) server.log("Night mode " + (value ? "enabled" : "disabled") + " on the device");
});

agent.on("homeweather.set.advance", function(value) {
    // Hitting 'Advance' takes the timer to the next trigger point.
    // If it's a second advance, that's the equivalent of 'no advance', so
    // just flip the value of 'advanceFlag'
    // NOTE This will not be sent by the agent if 'nightFlag' is false
    advanceFlag = !advanceFlag;
});

agent.on("homeweather.set.debug", function(value) {
    debug = value;
    server.log("Device debug messages " + (debug ? "enabled" : "disabled"));
});

agent.on("homeweather.set.settings", function(settings) {
    nightTime = settings.dimstart;
    dayTime = settings.dimend;
    nightFlag = settings.offatnight;

    if (debug) {
        server.log("Applying settings received from agent");
        if (nightFlag) {
            server.log(format("Display will dim at %ipm and come on at %iam", nightTime, dayTime));
        } else {
            server.log("Overnight display dimming disabled");
        }
    }
});

// Request a weather forecast from the agent - this will also update the settings
agent.send("homeweather.get.forecast", true);

// Start the app loop
heartbeat();
