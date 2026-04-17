using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

class ApiClient {

    private var _callback as Method?;

    function initialize() {
    }

    function send(records as Array<Dictionary>, callback as Method) as Void {
        _callback = callback;

        var apiBaseUrl = Properties.getValue("apiBaseUrl") as String?;
        if (apiBaseUrl == null || apiBaseUrl.length() == 0) {
            System.println("ApiClient: apiBaseUrl not configured");
            if (_callback != null) {
                _callback.invoke(0, null);
            }
            return;
        }

        var url = apiBaseUrl + "/api/v1/garmin/ingest";

        var deviceId = "garmin_fr265_unknown";
        if (records.size() > 0) {
            var firstRecord = records[0];
            var id = firstRecord.get("device_id");
            if (id != null && id instanceof String) {
                deviceId = id as String;
            }
        }

        var payload = {
            "records" => records,
            "device_id" => deviceId,
            "source" => "garmin_connect_iq",
            "upload_timestamp" => currentTimestamp()
        };

        var headers = {
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
            "X-Device-Id" => deviceId,
            "X-Platform" => "garmin_connect_iq",
            "X-Record-Type" => "samples",
            "X-Upload-Timestamp" => currentTimestamp()
        };

        var authToken = Properties.getValue("authToken") as String?;
        if (authToken != null && authToken.length() > 0) {
            headers.put("Authorization", "Bearer " + authToken);
        }

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, payload, options, method(:onResponse));
    }

    function onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200) {
            System.println("ApiClient: upload successful");
        } else if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE) {
            System.println("ApiClient: phone not connected");
        } else if (responseCode == Communications.NETWORK_REQUEST_TIMED_OUT) {
            System.println("ApiClient: request timed out");
        } else if (responseCode == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) {
            System.println("ApiClient: invalid response body");
        } else {
            System.println("ApiClient: HTTP " + responseCode);
        }

        if (_callback != null) {
            _callback.invoke(responseCode, data);
        }
    }

    private function currentTimestamp() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$T$4$:$5$:$6$Z", [
            info.year,
            info.month.format("%02d"),
            info.day.format("%02d"),
            info.hour.format("%02d"),
            info.min.format("%02d"),
            info.sec.format("%02d")
        ]);
    }
}
