// CONSTANTS
// HT16K33 registers and HT16K33-specific variables
const HT16K33_REGISTER_DISPLAY_ON  = "\x81";
const HT16K33_REGISTER_DISPLAY_OFF = "\x80";
const HT16K33_REGISTER_SYSTEM_ON   = "\x21";
const HT16K33_REGISTER_SYSTEM_OFF  = "\x20";
const HT16K33_DISPLAY_ADDRESS      = "\x00";
const HT16K33_I2C_ADDRESS          =  0x70;

// Convenience constants for bar colours
const LED_OFF = 0;
const LED_RED = 1;
const LED_YELLOW = 2;
const LED_GREEN = 3;

class HT16K33Bargraph {

    // Squirrel class for 24-bar bi-color LED bargraph display
    // driven by Holtek's HT16K33 controller, as used in the
    // Adafruit Bi-Color (Red/Green) 24-Bar Bargraph w/I2C Backpack Kit
    // https://www.adafruit.com/products/1721
    // Bus: I2C
    // Availibility: Device
    // Copyright 2015-17 Tony Smith (@smittytone)

    static VERSION = "1.0.1";

    // Class private properties
    _buffer = null;
    _led = null;
    _ledAddress = null;
    _barZeroByChip = true;
    _debug = false;

    constructor(i2cbus, i2cAddress = 0x70, debug = false) {
        // Parameters:
        // 1. Whichever configured imp I2C bus is to be used for the HT16K33
        // 2. The I2C address from the datasheet (0x70)
        // 3. Boolean, set/unset for debugging messages

        if (i2cbus == null) throw "HT16K33Bar requires a non-null Imp I2C bus";

        // Save bar graph's I2C details
        _led = i2cbus;
        _ledAddress = i2cAddress << 1;

        // Set the debugging flag
        if (typeof debug != "bool") debug = false;
        _debug = debug;

        // The buffer stores the colour values for each block of the bar
        _buffer = [0x0000, 0x0000, 0x0000];
    }

    function init(brightness = 15, barZeroByChip = true) {
        // Parameters:
        //   1. Integer, the initial brightness, 1-15 (default: 15)
        //   2. Boolean, to select whether bar zero is at the chip end of
        //      the board (true) or at the far end (false):
        //       ___________________________
        //      | o  [CHIP] [BARGRAPH LEDs] |
        //       ---------------------------
        //      bar number   0 . . . . . 23    barZeroByChip = true
        //      bar number   23 . . . . . 0    barZeroByChip = false
        // Returns: nothing

        local t = typeof barZeroByChip;
        if (t != "bool") {
            if (t == "float" || t == "integer") {
                barZeroByChip = (barZeroByChip.tointeger() == 0) ? false : true;
            } else {
                barZeroByChip = true;
            }
        }

        _barZeroByChip = barZeroByChip;

        // Power the display
        powerUp();

        // Set the brightness
        setBrightness(brightness);

        return this;
    }

    function fill(barNumber, ledColor) {
        // Fills all the bars up to and including the specified bar with the specified color
        // Parameters:
        //  1. Integer, the highest bar number to be lit (0-23)
        //  2. Integer, the colour of the bar
        // Returns: this

        if (barNumber < 0 || barNumber > 23) {
            server.error("HT16K33Bargraph.fill() passed out of range (0-23) bar number");
            return null;
        }

        if (ledColor < LED_OFF || ledColor > LED_GREEN) {
            server.error("HT16K33Bargraph.fill() passed out of range (0-2) LED colour");
            return null;
        }

        if (_barZeroByChip) {
            barNumber = 23 - barNumber;
            for (local i = 23 ; i > barNumber ; i--) {
                _setBar(i, ledColor);
            }
        } else {
            for (local i = 0 ; i < barNumber ; i++) {
                _setBar(i, ledColor);
            }
        }

        return this;
    }

    function set(barNumber, ledColor) {
        // Sets a specified bar’s color (off, red, green or yellow)
        // Parameters:
        //  1. Integer, the highest bar number to be lit (0-23); no default
        //  2. Integer, the colour of the bar
        // Returns: this

        if (barNumber < 0 || barNumber > 23) {
            server.error("HT16K33Bargraph.set() passed out of range (0-23) bar number");
            return null;
        }

        if (ledColor < LED_OFF || ledColor > LED_GREEN) {
            if (_debug) server.error("HT16K33Bargraph.set() passed out of range (0-2) LED colour");
            return null;
        }

        if (_barZeroByChip) barNumber = 23 - barNumber;
        _setBar(barNumber, ledColor);
        return this;
    }

    function clear() {
        // Clears the _buffer, which is then written to the LED matrix
        _buffer = [0x0000, 0x0000, 0x0000];
        return this;
    }

    function draw() {
        // Takes the contents of internal buffer and writes it to the LED matrix
        local dataString = HT16K33_DISPLAY_ADDRESS;
        for (local i = 0 ; i < 3 ; i++) {
            // Each _buffer entry is a 16-bit value - convert to two 8-bit values to write
            dataString = dataString + (_buffer[i] & 0xFF).tochar() + (_buffer[i] >> 8).tochar();
        }

        _led.write(_ledAddress, dataString);
    }

    function setBrightness(brightness = 15) {
        // Called when the app changes the brightness
        // Default: 15
        if (brightness > 15) brightness = 15;
        if (brightness < 0) brightness = 0;

        brightness = brightness + 224;

        // Write the new brightness value to the HT16K33
        _led.write(_ledAddress, brightness.tochar() + "\x00");
    }

    function powerDown() {
        _led.write(_ledAddress, HT16K33_REGISTER_DISPLAY_OFF);
        _led.write(_ledAddress, HT16K33_REGISTER_SYSTEM_OFF);
    }

    function powerUp() {
        _led.write(_ledAddress, HT16K33_REGISTER_SYSTEM_ON);
        _led.write(_ledAddress, HT16K33_REGISTER_DISPLAY_ON);
    }

    // ********** Private Functions - Do Not Call **********

    function _setBar(barNumber, ledColor) {
        // Sets a specific bar to the specified color
        // Called by set() and fill()
        local a = 999;
        local b = 999;

        if (barNumber < 12) {
            a = barNumber / 4;
        } else {
            a = (barNumber - 12) / 4;
        }

        b = barNumber % 4;
        if (barNumber >= 12) b = b + 4;

        a = a.tointeger();
        b = b.tointeger();

        if (ledColor == LED_RED) {
            // Turn red LED on, green LED off
            _buffer[a] = _buffer[a] | (1 << b);
            _buffer[a] = _buffer[a] & ~(1 << (b + 8));
        } else if (ledColor == LED_YELLOW) {
            // Turn red and green LED on
            _buffer[a] = _buffer[a] | (1 << b) | (1 << (b + 8));
        } else if (ledColor == LED_OFF) {
            // Turn red and green LED off
            _buffer[a] = _buffer[a] & ~(1 << b) & ~(1 << (b + 8));
        } else if (ledColor == LED_GREEN) {
            // Turn green LED on, red off
            _buffer[a] = _buffer[a] | (1 << (b + 8));
            _buffer[a] = _buffer[a] & ~(1 << b);
        }
    }
}
