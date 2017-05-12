// Home Weather - wall-mount weather Station
// Copyright Tony Smith, 2015-2017

#require "utilities.nut:1.0.0"

#import "../HT16K33Segment/HT16K33Segment.class.nut"

#import "../ht16k33matrix/ht16k33matrix.class.nut"

#import "../ht16k33bargraph/ht16k33bargraph.class.nut"

// SET DISCONNECTION POLICY

server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

// CONSTANTS

const LED_OFF = 0;
const LED_RED = 1;
const LED_AMBER = 2;
const LED_GREEN = 3;
const RECONNECT_TIME = 600.0;
local SWITCH_TIME = 2;

// GLOBALS

local matrix = null;
local segment = null;
local bar = null;
local savedForecast = null;
local now = null;
local hbTimer = null;
local disTimer = null;

local nightTime = 21;
local dayTime = 6;
local downtime = 0;

local offFlag = true;
local dimFlag = false;
local timeFlag = true;
local disFlag = false;
local displayFlag = false;
local debug = false;

local iconset = {};

// FUNCTIONS

function heartbeat() {
    // This function runs every 'SWITCH_TIME' seconds to manage the displays
    hbTimer = imp.wakeup(SWITCH_TIME, heartbeat);
    now = date();

    if (showDisplay()) {
        // The displays should be active
        if (!displayFlag) {
            // We have not set the 'display on' flag, so
            // set it and bring up the displays
            displayFlag = true;
            matrix.powerUp();
            bar.powerUp;
            segment.powerUp()
        }

        // Every 'SWITCH_TIME' seconds we display the temperature,
        // alternating with the time
        segment.clearDisplay();

        if (!timeFlag) {
            displayTemp(savedForecast);
        } else {
            displayTime();
        }

        timeFlag = !timeFlag;
    } else {
        // We should not  be showing the display
        if (displayFlag) {
            // If we have set the 'display on' flag,
            // unset it and power down the displays
            displayFlag = false;
            matrix.powerDown();
            bar.powerDown();
            segment.powerDown();
        }
    }
}

function showDisplay() {
    // Returns true if the display should be on, false otherwise
    local d = true;

    if (offFlag) {
        local h = now.hour;
        if (utilities.bstCheck()) ++h;
        if (h > 23) h = 0;
        if (h > nightTime || h < dayTime) {
            d = false;
            if (!dimFlag) {
                if (debug) server.log("Dimming display at " + h + "pm");
                dimFlag = true;
            }
        } else {
            d = true;
            if (dimFlag) {
                if (debug) server.log("Brightening display at " + h + "am");
                dimFlag = false;
            }
        }
    }

    return d;
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
    if (disFlag) {
        displayDisconnected();
        return;
    }

    // No data to display? Bail
    if (data == null || !displayFlag) return;

    // Temperature is in Celsius (see agent code)
    segment.clearBuffer(16);
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
    // No need to display the time? Bail
    if (!displayFlag) return;

    local h = now.hour;
    local m = 0;

    if (utilities.bstCheck()) ++h;
    if (h > 23) h = 0;

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

    segment.setColon(true);
    segment.updateDisplay();
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

    if (displayFlag) {
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

function bootMessage() {
    local a = split(imp.getsoftwareversion(), "-");
    server.log("impOS version " + a[2]);
    local i = imp.net.info();
    local w = i.interface[i.active];
    local s = ("connectedssid" in w) ? w.connectedssid : w.ssid;
    local t = (w.type == "wifi") ? "Connected by WiFi on SSID \"" + s + "\"" : "Ethernet";
    server.log(t + " with IP address " + i.ipv4.address);
}

// OFFLINE OPERATION FUNCTIONS

function disHandler(reason) {
    if (reason != SERVER_CONNECTED) {
        // Tell imp to wake in 'RECONNECT_TIME' minutes and attempt to reconnect
        disFlag = true;
        downtime = time();
        disTimer = imp.wakeup(RECONNECT_TIME, reconnect);
    } else {
        // Back online so request a weather forecast from the agent
        disFlag = false;
        downtime = time() - downtime;
        if (debug) server.log("Reconnected after " + downtime + " seconds");
        agent.send("homeweather.get.forecast", true);
    }
}

function reconnect() {
    disTimer = null;

    if (server.isconnected()) {
        disHandler(SERVER_CONNECTED);
    } else {
        server.connect(disHandler, 30);
    }
}

// START OF PROGRAM

// Register for unexpected disconnections
server.onunexpecteddisconnect(disHandler);

// Show boot message
bootMessage();

// Set up instanced classes
hardware.i2c89.configure(CLOCK_SPEED_400_KHZ);

matrix = HT16K33Matrix(hardware.i2c89, 0x70, true);
matrix.init(0, 3);

segment = HT16K33Segment(hardware.i2c89, 0x72);
segment.init(16, 4, false);

bar = HT16K33Bargraph(hardware.i2c89, 0x74, true);
bar.init(1, false);

// Load weather icons
iconset.clearday <- [0x89,0x42,0x18,0xBC,0x3D,0x18,0x42,0x91];
iconset.clearnight <- [0x0,0x0,0x0,0x81,0xE7,0x7E,0x3C,0x18];
iconset.rain <- [0x8C,0x5E,0x1E,0x5F,0x3F,0x9F,0x5E,0x0C];
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
agent.on("homeweather.set.dim.start", function(value) { nightTime = value; });
agent.on("homeweather.set.dim.end", function(value) { dayTime = value; });
agent.on("homeweather.set.offatnight", function(value) { offFlag = value; });
agent.on("homeweather.set.debug", function(value) { debug = value; });

// Request a weather forecast from the agent
agent.send("homeweather.get.forecast", true);

// Start the app loop
heartbeat();
