using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class DbxWearablesView extends WatchUi.View {

    private var _isSyncing as Boolean = false;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        // Title
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, 20, Graphics.FONT_SMALL, "dbxWearables", Graphics.TEXT_JUSTIFY_CENTER);

        // Subtitle
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, 48, Graphics.FONT_XTINY, "Garmin Health Sync", Graphics.TEXT_JUSTIFY_CENTER);

        // Divider line
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(centerX - 60, 70, centerX + 60, 70);

        // Sync status
        var status = Storage.getValue("lastSyncStatus") as String?;
        var count = Storage.getValue("lastSyncCount") as Number?;
        var totalSynced = Storage.getValue("totalSyncedCount") as Number?;
        var lastTs = Storage.getValue("lastSyncTimestamp") as String?;

        var statusY = 82;

        if (_isSyncing) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY, Graphics.FONT_TINY, "Syncing...", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (status != null && status.equals("ok")) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY, Graphics.FONT_TINY, "Sync OK", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (status != null && status.equals("error")) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY, Graphics.FONT_TINY, "Sync Error", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY, Graphics.FONT_TINY, "Not synced", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Last sync count
        if (count != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY + 26, Graphics.FONT_XTINY,
                "Last: " + count + " records", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Total synced
        if (totalSynced != null && totalSynced > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY + 48, Graphics.FONT_XTINY,
                "Total: " + totalSynced, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Last sync time
        if (lastTs != null) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height - 36, Graphics.FONT_XTINY,
                lastTs, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Tap hint at bottom
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, height - 18, Graphics.FONT_XTINY,
            "Tap to sync now", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function setSyncing(syncing as Boolean) as Void {
        _isSyncing = syncing;
        WatchUi.requestUpdate();
    }
}
