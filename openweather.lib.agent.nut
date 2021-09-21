/**
 * This class allows you to make one of two possible calls to OpenWeather’s
 * API. For more information, see https://openweathermap.org/api/one-call-api
 * Access to the API is controlled by key. Register for developer access
 * here: https://openweathermap.org/appid
 *
 * NOTE this class does not parse the incoming data, which is highly complex.
 *      It is up to your application to extract the data you require.
 *
 * @author    Tony Smith (@smittytone)
 * @copyright 20201
 * @license   MIT
 *
 * @class
 *
*/

class OpenWeather {

    static VERSION = "1.0.0";
    static FORECAST_URL = "https://api.openweathermap.org/data/2.5/onecall";

    // ********** Private Properties **********

    _apikey = null;
    _units = null;
    _lang = null;
    _excludes = null;
    _debug = false;

    /**
     * The Dark Sky construtor.
     *
     * @constructor
     *
     * @param {string} apiKey  - Your Open Weather service API key.
     * @param {bool}   [debug] - Whether to log extra debugging info (true) or not (false). Default: false.
     *
     * returns {instance} this
     *
    */
    constructor (key = null, debug = false) {
        // Check for instantiation parameter errors
        if (imp.environment() != ENVIRONMENT_AGENT) throw "OpenWeather() must be instantiated by the agent";
        if (key == "" || key = null) throw "OpenWeather() requires an API key";
        if (typeof key != "string") throw "OpenWeather() requires an API key supplied as a string";

        // Set private properties
        if (typeof debug != "bool") debug = false;
        _debug = debug;
        _units = "standard";
        _apikey = key;
    }

    /**
     * Make a request for future weather data.
     *
     * @param {float}    longitude  - Longitude of location for which a forecast is required.
     * @param {float}    latitude   - Latitude of location for which a forecast is required.
     * @param {function} [callback] - Optional asynchronous operation callback.
     *
     * @returns {table|string|null} If 'callback' is null, the function returns a table with key 'response';
     *                              if there was an error, the function returns a table with key 'error'.
     *                              If 'callback' is not null, the function returns nothing;
     *
    */
    function forecastRequest(latitude = 999.0, longitude = 999.0, callback = null) {
        // Check the supplied co-ordinates
        if (!_checkCoords(longitude, latitude, "forecastRequest")) {
            if (callback) {
                callback("Co-ordinate error", null);
                return;
            } else {
                return {"error": "Co-ordinate error"};
            }
        }

        // Co-ordinates good, so get a forecast
        local url = FORECAST_URL + "?lat=" + format("%.6f", latitude) + "&lon=" + format("%.6f", longitude) + "&appid=" + _apikey;
        url = _addOptions(url);
        return _sendRequest(http.get(url), callback);
    }

    /**
     * Specify the preferred weather report's units.
     *
     * @param {string} [units] - Country code indicating the type of units. Default: automatic, based on location.
     *
     * @returns {instance} The Dark Sky instance (this).
     *
    */
    function setUnits(units = "standard") {
        local types = ["metric", "imperal", "standard"];
        local match = false;
        units = units.tolower();
        foreach (type in types) {
            if (units == type) {
                match = true;
                break;
            }
        }

        if (!match) {
            if (_debug) server.error("OpenWeather.setUnits() incorrect units option selected (" + units + "); using default value (standard)");
            units = "standard";
        }

        _units = units;
        if (_debug) server.log("OpenWeather units selected: " + _units);
        return this;
    }

    /**
     * Specify the preferred weather report's language.
     *
     * @param {string} [language] - Country code indicating the language. Default: English.
     *
     * @returns {instance} The Dark Sky instance (this).
     *
    */
    function setLanguage(language = "en") {
        local types = ["af", "al", "ar", "az", "bg", "ca", "cz", "da", "de", "el", "en", "eu", "fa", "fi",
                       "fr", "gl", "he", "hi", "hr", "hu", "id", "it", "ja", "kr", "la", "lt", "mk", "no",
                       "nl", "pl", "pt", "pt_br", "ro", "ru", "se", "sv", "sk", "sl", "sp", "es", "sr",
                       "th", "tr", "ua", "uk", "vi", "zh_cn", "zh_tw", "zu"];
        local match = false;
        language = language.tolower();
        foreach (type in types) {
            if (language == type) {
                match = true;
                break;
            }
        }

        if (!match) {
            if (_debug) server.error("OpenWeather.setLanguage() incorrect language option selected (" + language + "); using default value (en)");
            language = "en";
        }

        _lang = language;
        if (_debug) server.log("OpenWeather language selected: " + _lang);
        return this;
    }

    function exclude(list = []) {
        local types = ["current", "minutely", "hourly", "daily", "alerts"];
        local matches = [];
        foreach (item in list) {
            foreach (type in types) {
                if (item == type) matches.append(item);
            }
        }

        if (matches.len() == 0) {
            if (_debug) server.error("OpenWeather.exclude() incorrect exlcusions passed");
            return this;
        }

        _excludes = "";
        foreach (item in matches) {
            _excludes += (item + ",");
        }

        if (_excludes.len() > 0) _excludes = _excludes.slice(0, _excludes.len() - 1);
        if (_debug) server.log("OpenWeather excludes set: " + _excludes);
        return this;
    }

    // ********** PRIVATE FUNCTIONS - DO NOT CALL **********

    /**
     * Send a request to Dark Sky.
     *
     * @private
     *
     * @param {imp::httprequest} req  - The HTTPS request to send.
     * @param {function}         [cb] - Optional callback function.
     *
     * @returns {imp::httpresponse|null} The HTTPS response, or nothing if 'cb' is not null.
     *
    */
    function _sendRequest(req, cb = null) {
        if (cb != null) {
            req.sendasync(function(resp) {
                local returnTable = _processResponse(resp);
                cb(returnTable.err, returnTable.data);
            }.bindenv(this));
            return null;
        } else {
            local resp = req.sendsync();
            return _processResponse(resp);
        }
    }

    /**
     * @typedef {table} decoded
     *
     * @property {string|null} err  - An error message, if an error occurred.
     * @property {table|null}  data - The response data.
     */

    /**
     * Process a response received from Dark Sky.
     *
     * @private
     *
     * @param {imp::httpresponse} resp - The HTTPS response.
     *
     * @returns {decoded} The latest request count, or -1 on error.
     *
    */
    function _processResponse(resp) {
        local err, data, count;
        if (resp.statuscode != 200) {
            err = format("Unable to retrieve forecast data (code: %i)", resp.statuscode);
        } else {
            try {
                // Have we valid JSON?
                data = http.jsondecode(resp.body);
            } catch(exp) {
                err = "Unable to decode data received from Open Weather: " + exp;
                data = null;
            }
        }

        return {"err" : err, "data" : data};
    }

    /**
     * Check that valid co-ords have been supplied.
     *
     * @private
     *
     * @param {float}  longitude - Longitude of location for which a forecast is required.
     * @param {float}  latitude  - Latitude of location for which a forecast is required.
     * @param {string} caller    - The name of the calling function, for error reporting.
     *
     * @returns {Boolean} Whether the supplied co-ordinates are valid (true) or not (false).
     *
    */
    function _checkCoords(longitude = 999.0, latitude = 999.0, caller = "function") {
        if (typeof longitude != "float") {
            try {
                longitude = longitude.tofloat();
            } catch (err) {
                if (_debug) server.error("DarkSky." + caller + "() can't process supplied longitude value");
                return false;
            }
        }

        if (typeof latitude != "float") {
            try {
                latitude = latitude.tofloat();
            } catch (err) {
                if (_debug) server.error("DarkSky." + caller + "() can't process supplied latitude value");
                return false;
            }
        }

        if (longitude == 999.0 || latitude == 999.0) {
            if (_debug) server.error("DarkSky." + caller + "() requires valid latitude/longitude co-ordinates");
            return false;
        }

        if (latitude > 90.0 || latitude < -90.0) {
            if (_debug) server.error("DarkSky." + caller + "() requires valid a latitude co-ordinate (value out of range)");
            return false;
        }

        if (longitude > 180.0 || longitude < -180.0) {
            if (_debug) server.error("DarkSky." + caller + "() requires valid a latitude co-ordinate (value out of range)");
            return false;
        }

        return true;
    }

    /**
     * Add URL-encoded options to the request URL. Used when assembling HTTPS requests.
     *
     * @private
     *
     * @param {string} [baseurl] - Optional base URL.
     *
     * @returns {string} The full URL will added options
     *
    */
    function _addOptions(baseurl = "") {
        local opts = "&units=" + _units;
        if (_lang) opts += "&lang=" + _lang;
        if (_excludes) opts += "&exclude=" + _excludes;
        return (baseurl + opts);
    }
}
