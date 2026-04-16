using Toybox.Lang;
using Toybox.WatchUi;

class DbxWearablesDelegate extends WatchUi.BehaviorDelegate {

    private var _view as DbxWearablesView;

    function initialize(view as DbxWearablesView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        triggerManualSync();
        return true;
    }

    function onTap(evt as ClickEvent) as Boolean {
        triggerManualSync();
        return true;
    }

    private function triggerManualSync() as Void {
        _view.setSyncing(true);

        var collector = new SensorCollector();
        var records = collector.collectAll();

        if (records.size() == 0) {
            _view.setSyncing(false);
            return;
        }

        var client = new ApiClient();
        client.send(records, method(:onManualSyncComplete));
    }

    function onManualSyncComplete(responseCode as Number, data as Dictionary or String or Null) as Void {
        var count = 0;
        var storedRecords = Application.Storage.getValue("pendingRecordCount");
        if (storedRecords != null && storedRecords instanceof Number) {
            count = storedRecords as Number;
        }

        if (responseCode == 200) {
            Application.Storage.setValue("lastSyncStatus", "ok");
            Application.Storage.setValue("lastSyncCount", count);

            var now = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            var ts = Lang.format("$1$:$2$", [
                now.hour.format("%02d"),
                now.min.format("%02d")
            ]);
            Application.Storage.setValue("lastSyncTimestamp", ts);

            var totalSynced = Application.Storage.getValue("totalSyncedCount");
            if (totalSynced == null) { totalSynced = 0; }
            Application.Storage.setValue("totalSyncedCount", (totalSynced as Number) + count);
        } else {
            Application.Storage.setValue("lastSyncStatus", "error");
        }

        _view.setSyncing(false);
    }
}
