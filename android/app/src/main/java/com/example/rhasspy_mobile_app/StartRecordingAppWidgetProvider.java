package com.example.rhasspy_mobile_app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;

import android.util.Log;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.FlutterNativeView;

public class StartRecordingAppWidgetProvider extends AppWidgetProvider {
    private static final String CHANNEL = "rhasspy_mobile_app/widget";
    private static MethodChannel channel = null;
    private static FlutterNativeView backgroundFlutterView = null;


    @Override
    public void onEnabled(Context context) {
        Log.i("HomeScreenWidget", "onEnabled!");
    }
    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds){
            Intent intent = new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
            intent.putExtra("StartRecording","");
            PendingIntent pendingIntent = PendingIntent.getActivity(context,0,intent,PendingIntent.FLAG_UPDATE_CURRENT);
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.start_recording_widget);
            views.setOnClickPendingIntent(R.id.start_recording_widget_button, pendingIntent);
            appWidgetManager.updateAppWidget(appWidgetId, views);
            Log.i("HomeScreenWidget", "onUpdate!");


        }
        super.onUpdate(context, appWidgetManager, appWidgetIds);
    }
}
