using Toybox.Application;
using Toybox.Background;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

(:background)
class DbxWearablesApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        registerBackgroundSync();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new DbxWearablesView();
        var delegate = new DbxWearablesDelegate(view);
        return [view, delegate];
    }

    function getServiceDelegate() as [ServiceDelegate] {
        return [new BackgroundService()];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            var dict = data as Dictionary;
            var status = dict.get("status");
            var count = dict.get("count");
            var ts = dict.get("timestamp");

            Storage.setValue("lastSyncStatus", status);
            if (count != null) {
                Storage.setValue("lastSyncCount", count);
            }
            if (ts != null) {
                Storage.setValue("lastSyncTimestamp", ts);
            }

            var totalSynced = Storage.getValue("totalSyncedCount");
            if (totalSynced == null) {
                totalSynced = 0;
            }
            if (count != null && count instanceof Number) {
                Storage.setValue("totalSyncedCount", (totalSynced as Number) + (count as Number));
            }
        }

        WatchUi.requestUpdate();
    }

    function registerBackgroundSync() as Void {
        var intervalMinutes = Application.Properties.getValue("syncIntervalMinutes");
        if (intervalMinutes == null || !(intervalMinutes instanceof Number) || (intervalMinutes as Number) < 5) {
            intervalMinutes = 5;
        }

        var intervalSeconds = (intervalMinutes as Number) * 60;
        var nextEvent = Time.now().add(new Time.Duration(intervalSeconds));

        try {
            Background.registerForTemporalEvent(nextEvent);
        } catch (e instanceof Background.InvalidBackgroundTimeException) {
            System.println("Background registration failed: " + e.getErrorMessage());
        }
    }

    function onStop(state as Dictionary?) as Void {
        Background.deleteTemporalEvent();
    }
}
