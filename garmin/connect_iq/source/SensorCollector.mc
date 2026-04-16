using Toybox.ActivityMonitor;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

(:background)
class SensorCollector {

    private const STORAGE_KEY_LAST_COLLECT = "lastCollectMoment";
    private const MAX_SAMPLES_PER_TYPE = 60;

    function initialize() {
    }

    function collectAll() as Array<Dictionary> {
        var records = [] as Array<Dictionary>;
        var since = getLastCollectMoment();
        var now = Time.now();
        var deviceId = getDeviceId();

        collectHeartRate(records, since, deviceId);
        collectStress(records, since, deviceId);
        collectBodyBattery(records, since, deviceId);
        collectOxygenSaturation(records, since, deviceId);
        collectSteps(records, deviceId);

        Storage.setValue(STORAGE_KEY_LAST_COLLECT, now.value());
        Storage.setValue("pendingRecordCount", records.size());

        return records;
    }

    private function collectHeartRate(
        records as Array<Dictionary>,
        since as Time.Moment,
        deviceId as String
    ) as Void {
        if (!(SensorHistory has :getHeartRateHistory)) {
            return;
        }

        var iterator = SensorHistory.getHeartRateHistory({
            :period => MAX_SAMPLES_PER_TYPE,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });

        if (iterator == null) { return; }

        var sample = iterator.next();
        var count = 0;
        while (sample != null && count < MAX_SAMPLES_PER_TYPE) {
            if (sample.when != null && sample.when.compare(since) > 0 && sample.data != null) {
                records.add(buildRecord(
                    "heart_rate_intraday", sample.data.toFloat(), "bpm",
                    sample.when, deviceId
                ));
            }
            sample = iterator.next();
            count++;
        }
    }

    private function collectStress(
        records as Array<Dictionary>,
        since as Time.Moment,
        deviceId as String
    ) as Void {
        if (!(SensorHistory has :getStressHistory)) {
            return;
        }

        var iterator = SensorHistory.getStressHistory({
            :period => MAX_SAMPLES_PER_TYPE,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });

        if (iterator == null) { return; }

        var sample = iterator.next();
        var count = 0;
        while (sample != null && count < MAX_SAMPLES_PER_TYPE) {
            if (sample.when != null && sample.when.compare(since) > 0
                && sample.data != null && sample.data != 127) {
                records.add(buildRecord(
                    "stress_level", sample.data.toFloat(), "score",
                    sample.when, deviceId
                ));
            }
            sample = iterator.next();
            count++;
        }
    }

    private function collectBodyBattery(
        records as Array<Dictionary>,
        since as Time.Moment,
        deviceId as String
    ) as Void {
        if (!(SensorHistory has :getBodyBatteryHistory)) {
            return;
        }

        var iterator = SensorHistory.getBodyBatteryHistory({
            :period => MAX_SAMPLES_PER_TYPE,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });

        if (iterator == null) { return; }

        var sample = iterator.next();
        var count = 0;
        while (sample != null && count < MAX_SAMPLES_PER_TYPE) {
            if (sample.when != null && sample.when.compare(since) > 0 && sample.data != null) {
                records.add(buildRecord(
                    "body_battery_current", sample.data.toFloat(), "score",
                    sample.when, deviceId
                ));
            }
            sample = iterator.next();
            count++;
        }
    }

    private function collectOxygenSaturation(
        records as Array<Dictionary>,
        since as Time.Moment,
        deviceId as String
    ) as Void {
        if (!(SensorHistory has :getOxygenSaturationHistory)) {
            return;
        }

        var iterator = SensorHistory.getOxygenSaturationHistory({
            :period => MAX_SAMPLES_PER_TYPE,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });

        if (iterator == null) { return; }

        var sample = iterator.next();
        var count = 0;
        while (sample != null && count < MAX_SAMPLES_PER_TYPE) {
            if (sample.when != null && sample.when.compare(since) > 0 && sample.data != null) {
                records.add(buildRecord(
                    "spo2", sample.data.toFloat(), "pct",
                    sample.when, deviceId
                ));
            }
            sample = iterator.next();
            count++;
        }
    }

    private function collectSteps(
        records as Array<Dictionary>,
        deviceId as String
    ) as Void {
        var info = ActivityMonitor.getInfo();
        if (info == null || info.steps == null) {
            return;
        }

        records.add(buildRecord(
            "steps_intraday", info.steps.toFloat(), "count",
            Time.now(), deviceId
        ));
    }

    private function buildRecord(
        metricType as String,
        value as Float,
        unit as String,
        when as Time.Moment,
        deviceId as String
    ) as Dictionary {
        return {
            "metric_type" => metricType,
            "value" => value,
            "unit" => unit,
            "recorded_at" => formatTimestamp(when),
            "device_id" => deviceId,
            "source" => "garmin_connect_iq"
        };
    }

    private function formatTimestamp(moment as Time.Moment) as String {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$T$4$:$5$:$6$Z", [
            info.year,
            info.month.format("%02d"),
            info.day.format("%02d"),
            info.hour.format("%02d"),
            info.min.format("%02d"),
            info.sec.format("%02d")
        ]);
    }

    private function getLastCollectMoment() as Time.Moment {
        var stored = Storage.getValue(STORAGE_KEY_LAST_COLLECT);
        if (stored != null && stored instanceof Number) {
            return new Time.Moment(stored as Number);
        }
        // Default: 10 minutes ago
        return Time.now().subtract(new Time.Duration(600));
    }

    private function getDeviceId() as String {
        var settings = System.getDeviceSettings();
        var serial = settings.uniqueIdentifier;
        if (serial != null) {
            return "garmin_fr265_" + serial;
        }
        return "garmin_fr265_unknown";
    }
}
