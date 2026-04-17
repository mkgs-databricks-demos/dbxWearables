using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Application.Storage;

(:background)
class BackgroundService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var collector = new SensorCollector();
        var records = collector.collectAll();

        if (records.size() == 0) {
            Background.exit({
                "status" => "ok",
                "count" => 0,
                "timestamp" => currentTimestamp()
            });
            return;
        }

        var apiBaseUrl = Properties.getValue("apiBaseUrl") as String?;
        if (apiBaseUrl == null || apiBaseUrl.length() == 0) {
            Background.exit({
                "status" => "error",
                "count" => 0,
                "timestamp" => currentTimestamp()
            });
            return;
        }

        var url = apiBaseUrl + "/api/v1/garmin/ingest";
        var deviceId = records[0].get("device_id") as String;

        var payload = {
            "records" => records,
            "device_id" => deviceId != null ? deviceId : "garmin_fr265_unknown",
            "source" => "garmin_connect_iq",
            "upload_timestamp" => currentTimestamp()
        };

        var headers = {
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
            "X-Device-Id" => deviceId != null ? deviceId : "garmin_fr265_unknown",
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
        var recordCount = Storage.getValue("pendingRecordCount");
        if (recordCount == null) { recordCount = 0; }

        if (responseCode == 200) {
            reregisterBackgroundEvent();

            Background.exit({
                "status" => "ok",
                "count" => recordCount,
                "timestamp" => currentTimestamp()
            });
        } else {
            System.println("Background sync failed: HTTP " + responseCode);
            reregisterBackgroundEvent();

            Background.exit({
                "status" => "error",
                "count" => 0,
                "timestamp" => currentTimestamp()
            });
        }
    }

    private function reregisterBackgroundEvent() as Void {
        var intervalMinutes = Properties.getValue("syncIntervalMinutes");
        if (intervalMinutes == null || !(intervalMinutes instanceof Number) || (intervalMinutes as Number) < 5) {
            intervalMinutes = 5;
        }

        var intervalSeconds = (intervalMinutes as Number) * 60;
        var nextEvent = Time.now().add(new Time.Duration(intervalSeconds));

        try {
            Background.registerForTemporalEvent(nextEvent);
        } catch (e) {
            System.println("Failed to re-register background event: " + e.getErrorMessage());
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
