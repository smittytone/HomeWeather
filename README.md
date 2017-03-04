# HomeWeather 2.2

This software powers a home weather station based on the Electric Imp Platform.

## The Hardware

The station comprises an imp001 and April breakout board, plus an [Adafruit 0.56in seven-segment LED](https://www.adafruit.com/products/878), an [Adafruit 1.2in LED matrix display](https://www.adafruit.com/products/1856) and an [Adafruit bicolor LED bar](https://www.adafruit.com/products/1721). The display units connect to the imp001/April via I&sup2;C &mdash; it’s just a matter of wiring them all up to a single pair of imp I&sup2;C pins plus GND and 3V3. A larger solderless breadboard should accomodate them all.

## Dark Sky

The station uses [Dark Sky](https://darksky.net/)’s Dark Sky API for regular weather forecasts. This requires a developer account, which is free &mdash; register [here](https://darksky.net/dev/register). The Dark Sky API is a commercial service. Though the first 1000 API calls made each day under your API key are free of charge, subsequent calls are billed at a rate of $0.0001 per call. You and your application will not be notified by the [Electric Imp Dark Sky library](https://electricimp.com/docs/libraries/webservices/darksky/) if this occurs, so you may wish to add suitable call-counting code to your application.

### Dark Sky Units

The code is set to deliver Dark Sky forecast in UK units. You may wish to change this according to your location. Look for line 161 in the agent code.

## Build API Integration

The agent code makes use of [Electric Imp’s Build API](https://electricimp.com/docs/buildapi/) to acquire code version data. You can get your own Build API key by logging into the Electric Imp IDE and selecting ‘Build API Keys’ from the Username menu in the top right.

You can also comment out Build-related lines 186-188 to remove this functionality.

You can find more information about the integration [here](https://electricimp.com/docs/libraries/utilities/buildapiagent/).

## Squinter

The code makes use of the accompanying library, HT16K33Bar, in the file `ht16k33bar.class.nut`. If you are using the macOS tool Squinter (download [here](https://electricimp.com/docs/attachments/squinter/squinter_1_0_119.zip)) to manage your Electric Imp projects, the device code is set up (line 5) to import and pre-process this file. Alternatively, you can simply paste in the file contents over line 5.