package com.example.rhasspy_mobile_app;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.PersistableBundle;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.List;
import java.util.Objects;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;
import io.flutter.view.FlutterCallbackInformation;
import io.flutter.view.FlutterMain;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "rhasspy_mobile_app/widget";
    private MethodChannel channel = null;
    public MethodChannel channel2;

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState, @Nullable PersistableBundle persistentState) {
        super.onCreate(savedInstanceState, persistentState);
        if (!isTaskRoot()
                && getIntent().hasCategory(Intent.CATEGORY_LAUNCHER)
                && getIntent().getAction() != null
                && getIntent().getAction().equals(Intent.ACTION_MAIN)) {

            finish();
            return;
        }


    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        Bundle extras = getIntent().getExtras();
        channel = getMethodChannel(flutterEngine);
        if(extras != null && extras.containsKey("StartRecording"))  {
            channel.invokeMethod("StartRecording","test");
            Log.i("Home", extras.getString("StartRecording"));

        }

        super.configureFlutterEngine(flutterEngine);
         channel2 =new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "rhasspy_mobile_app");
        channel2.setMethodCallHandler((call, result) -> {
            if(call.method.equals("sendToBackground")){
                Log.i("Background", "sendToBackground");
                moveTaskToBack(true);
            }
        });
    }


    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        Log.i("Home", "NewIntent");
        if(intent.getExtras() != null) {
            if (Objects.requireNonNull(intent.getExtras()).containsKey("StartRecording")) {
                Log.i("Home", intent.getExtras().getString("StartRecording"));
                if (channel == null) {
                    channel = getMethodChannel(null);
                }
                channel.invokeMethod("StartRecording", "");
            }
        }


    }

    private MethodChannel getMethodChannel(FlutterEngine engine) {
        Context context = getApplicationContext();
        FlutterMain.startInitialization(context);
        FlutterMain.ensureInitializationComplete(context, new String[]{""});


        // Instantiate a FlutterEngine.
        if(engine == null){
            engine = new FlutterEngine(context);
        }
        DartExecutor.DartEntrypoint entryPoint = new DartExecutor.DartEntrypoint(FlutterMain.findAppBundlePath(),"");
        engine.getDartExecutor().executeDartEntrypoint(entryPoint);
        return new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
    }


}

