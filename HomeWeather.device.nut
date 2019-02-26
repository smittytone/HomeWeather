// Home Weather - wall-mount weather Station
// Copyright Tony Smith, 2015-2019

// ********** IMPORTS **********
// If you are NOT using Squinter or a similar tool, replace the following #import statement(s)
// with the contents of the named file(s):
#import "../generic/crashReporter.nut"                      // Source: https://github.com/smittytone/generic
#import "../generic/utilities.nut"                          // Source: https://github.com/smittytone/generic
#import "../generic/disconnect.nut"                         // Source: https://github.com/smittytone/generic
#import "../Location/location.class.nut"                    // Source: https://github.com/smittytone/Location
#import "../ht16k33segment/ht16k33segment.class.nut"        // Source: https://github.com/smittytone/HT16K33Segment
#import "../ht16k33matrix/ht16k33matrix.class.nut"          // Source: https://github.com/smittytone/HT16K33Matrix
#import "../ht16k33bargraph/ht16k33bargraph.class.nut"      // Source: https://github.com/smittytone/HT16K33Bargraph


// ********** CONSTANTS **********
const LED_OFF = 0;
const LED_RED = 1;
const LED_AMBER = 2;
const LED_GREEN = 3;
const DISPLAY_ON = 0xFF;
const DISPLAY_OFF = 0x00;
const RECONNECT_TIMEOUT = 30;
const RECONNECT_DELAY = 61;
const SWITCH_TIME = 2;


// ********** GLOBAL VARIABLES **********
local matrix = null;
local segment = null;
local bar = null;
local iconset = null;
local savedForecast = null;
local now = null;
local hbTimer = null;
local reconnectTimer = null;
local locator = null;
local nightTime = 23;
local dayTime = 8;
local displayState = DISPLAY_ON;
local isNight = false;
local isAdvanceSet = false;
local timeFlag = true;
local isDisconnected = false;
local isConnecting = false;
local debug = false;


// ********** DISPLAY FUNCTIONS **********
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
            if (debug) server.log("Brightening display at " + now.hour + ":00 hours");
        }

        // Every 'SWITCH_TIME' seconds we display the temperature, alternating with the time
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
            if (debug) server.log("Dimming display at " + now.hour + ":00 hours");
        }
    }
}

function showDisplay(hour, minute) {
    // Returns true if the display should be on, false otherwise - default is true / on
    // If we have auto-dimming set, we need only check whether we need to turn the display off
    local returnValue = true;
    if (isNight && (hour == dayTime || hour == nightTime) && isAdvanceSet) isAdvanceSet = false;
    if (isNight && (hour < dayTime || hour >= nightTime)) returnValue = false;
    return (isAdvanceSet ? !returnValue : returnValue);
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

function displayTemp(data) {
    // Clear the display
    segment.clearDisplay();

    // Disconnected? Indicate on the display and bail
    if (isDisconnected) {
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
                segment.writeGlyph(0, 0);
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
    segment.writeGlyph(4, 0x63).setColon(false).updateDisplay();
}

function displayTime() {
    // Clear the display
    segment.clearDisplay();

    local h = now.hour;
    local m = 0;

    if (h < 10) {
        segment.writeGlyph(0, 0, false);
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
            m++;
        }

        segment.writeNumber(4, (now.min - (10 * (m - 1))), false);
        segment.writeNumber(3, m - 1, false);
    } else {
        segment.writeNumber(4, now.min, false);
        segment.writeNumber(3, 0, false);
    }

    // Add the colon and update the display
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

    // Save the current forecast for next time, in case the function is NOT triggered
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
    // First display the forecast text
    matrix.displayLine(data.cast);

    local icon = null;
    // Use a 'try... catch' in case the table 'iconset' has no key
    // that matches the string 'data.icon' (choose 'none' if that's the case)
    try {
        icon = iconset[data.icon];
    } catch (error) {
        icon = iconset.none;
    }

    // Display the weather icon
    //matrix.displayIcon(icon);
    matrix.displayCharacter(icon);
}

function setIcons() {
    // Set up the character matrices within 'iconset'
    iconset = {};
    iconset.clearday <-     [0x89,0x42,0x18,0xBC,0x3D,0x18,0x42,0x91];
    iconset.clearnight <-   [0x0,0x0,0x0,0x81,0xE7,0x7E,0x3C,0x18];
    iconset.rain <-         [0x8C,0x5E,0x1E,0x5F,0x3F,0x9F,0x5E,0x0C];
    iconset.lightrain <-    [0x8C,0x52,0x12,0x51,0x31,0x91,0x52,0xC];
    iconset.snow <-         [0x14,0x49,0x2A,0x1C,0x1C,0x2A,0x49,0x14];
    iconset.sleet <-        [0x4C,0xBE,0x5E,0xBF,0x5F,0xBF,0x5E,0xAC];
    iconset.wind <-         [0x28,0x28,0x28,0x28,0x28,0xAA,0xAA,0x44];
    iconset.fog <-          [0x55,0xAA,0x55,0xAA,0x55,0xAA,0x55,0xAA];
    iconset.cloudy <-       [0x0C,0x1E,0x1E,0x1F,0x1F,0x1F,0x1E,0x0C];
    iconset.partlycloudy <- [0x0C,0x12,0x12,0x11,0x11,0x11,0x12,0x0C];
    iconset.thunderstorm <- [0x0,0x0,0x0,0xF0,0x1C,0x7,0x0,0x0];
    iconset.tornado <-      [0x0,0x2,0x36,0x7D,0xDD,0x8D,0x6,0x2];
    iconset.none <-         [0x0,0x0,0x2,0xB9,0x9,0x6,0x0,0x0];
}

function displayDisconnected() {
    // Put 'dISC' or 'COnn' onto the segment display to indicate status
    if (!isConnecting) {
        // 'dISC'
        segment.writeChar(0, 0x5E, false);
        segment.writeChar(1, 0x06, false);
        segment.writeChar(3, 0x6D, false);
        segment.writeChar(4, 0x39, false);
    } else {
        // 'CONN'
        segment.writeChar(0, 0x39, false);
        segment.writeChar(1, 0x3F, false);
        segment.writeChar(3, 0x37, false);
        segment.writeChar(4, 0x37, false);
    }
    segment.updateDisplay();
}

// ********** OFFLINE OPERATION FUNCTIONS **********
function discHandler(event) {
    // Called if the server connection is broken or re-established
    if ("message" in event && debug) server.log("Connection Manager: " + event.message);

    if ("type" in event) {
        if (event.type == "disconnected") {
            isDisconnected = true;
            isConnecting = false;
        } else if (event.type == "connecting") {
            isConnecting = true;
        } else if (event.type == "connected") {
            isDisconnected = false;
            isConnecting = false;

            // Get an updated forecast from the agent
            agent.send("homeweather.get.forecast", true);
        }
    }
}


// ********** RUNTIME START **********

// ADDED IN 2.7.0
// Set up the crash reporter
crashReporter.init();

// Load in generic boot message code
// If you are NOT using Squinter or a similar tool, replace the following #import statement(s)
// with the contents of the named file(s):
#import "../generic/bootmessage.nut"        // Source code: https://github.com/smittytone/generic

// Set up the disconnection manager
disconnectionManager.eventCallback = discHandler;
disconnectionManager.reconnectDelay = RECONNECT_DELAY;
disconnectionManager.reconnectTimeout = RECONNECT_TIMEOUT;
disconnectionManager.start();

// Instantiate the location finder
locator = Location();

// Set up the matrix display
hardware.i2c89.configure(CLOCK_SPEED_400_KHZ);
matrix = HT16K33Matrix(hardware.i2c89, 0x70);
matrix.init(1, 3);

// ADDED IN 2.7.0
// Set up weather icons using user-definable characters
matrix.defineCharacter(0, "\x89\x42\x18\xBC\x3D\x18\x42\x91");
matrix.defineCharacter(1, "\x8C\x5E\x1E\x5F\x3F\x9F\x5E\x0C");
matrix.defineCharacter(2, "\x8C\x52\x12\x51\x31\x91\x52\x0C");
matrix.defineCharacter(3, "\x14\x49\x2A\x1C\x1C\x2A\x49\x14");
matrix.defineCharacter(4, "\x4C\xBE\x5E\xBF\x5F\xBF\x5E\xAC");
matrix.defineCharacter(5, "\x14\x14\x14\x14\x14\x55\x55\x22");
matrix.defineCharacter(6, "\x55\xAA\x55\xAA\x55\xAA\x55\xAA");
matrix.defineCharacter(7, "\x0C\x1E\x1E\x1F\x1F\x1F\x1E\x0C");
matrix.defineCharacter(8, "\x0C\x12\x12\x11\x11\x11\x12\x0C");
matrix.defineCharacter(9, "\x00\x00\x00\xF0\x1C\x07\x00\x00");
matrix.defineCharacter(10, "\x00\x02\x36\x7D\xDD\x8D\x06\x02");
matrix.defineCharacter(11, "\x3C\x42\x81\xC3\xFF\xFF\x7E\x3C");
matrix.defineCharacter(12, "\x00\x00\x02\xB9\x09\x06\x00\x00");

// Set up a table to map incoming weather condition names
// (eg. "clearday") to user-definable character Ascii values
iconset = {};
iconset.clearday     <- 0;
iconset.rain         <- 1;
iconset.lightrain    <- 2;
iconset.snow         <- 3;
iconset.sleet        <- 4;
iconset.wind         <- 5;
iconset.fog          <- 6;
iconset.cloudy       <- 7;
iconset.partlycloudy <- 8;
iconset.thunderstorm <- 9;
iconset.tornado      <- 10;
iconset.clearnight   <- 11;
iconset.none         <- 12;

// Set up the segment display
segment = HT16K33Segment(hardware.i2c89, 0x72);
segment.init(16, 1, false);

// Set up the bar
bar = HT16K33Bargraph(hardware.i2c89, 0x74);
bar.init(1, false);

// Set up agent interaction
agent.on("homeweather.show.forecast", displayWeather);

agent.on("homeweather.set.dim.start", function(value) {
    // Handle a message setting the night mode dimmer start time
    nightTime = value;
    if (debug) server.log("Display off time set to " + value);
});

agent.on("homeweather.set.dim.end", function(value) {
    // Handle a message setting the night mode dimmer end time
    dayTime = value;
    if (debug) server.log("Display on time set to " + value);
});

agent.on("homeweather.set.offatnight", function(value) {
    // Handle a message enabling or disabling the night mode dimmer
    isNight = value;
    if (debug) server.log("Night mode " + (value ? "enabled" : "disabled") + " on the device");
});

agent.on("homeweather.set.advance", function(value) {
    // Hitting 'Advance' takes the timer to the next trigger point.
    // If it's a second advance, that's the equivalent of 'no advance', so
    // just flip the value of 'isAdvanceSet'
    // NOTE This will not be sent by the agent if 'isNight' is false
    isAdvanceSet = !isAdvanceSet;
});

agent.on("homeweather.set.debug", function(value) {
    // Handle a message enabling or disabling extra debug logging
    debug = value;
    server.log("Device debug messages " + (debug ? "enabled" : "disabled"));
});

agent.on("homeweather.set.settings", function(settings) {
    // Handle a message sending the application settings
    nightTime = settings.dimstart;
    dayTime = settings.dimend;
    isNight = settings.offatnight;

    if (debug) {
        server.log("Applying settings received from agent");
        server.log(isNight
            ? format("Display will dim at %i:00 and come on at %i:00", nightTime, dayTime)
            : "Overnight display dimming disabled");
    }
});

// Request a weather forecast from the agent - this will also update the settings
agent.send("homeweather.get.forecast", true);

// Start the app loop
heartbeat();
