package com.example.rhasspy_mobile_app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Binder;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import java.io.ByteArrayOutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketException;
import java.net.UnknownHostException;

public class WakeWordService extends Service {

    public class LocalBinder extends Binder {
        WakeWordService getService() {
            return WakeWordService.this;
        }
    }

    private AudioRecord recorder;
    private static int BUFFER_SIZE = 2048;
    private static long byteRate = 16 * 16000 * 1 / 8;
    private int sampleRate = 16000;
    public boolean isActive = false;
    private static String TAG = "WakeWord";
    public boolean isPaused = false;
    private final IBinder binder = new LocalBinder();
    private InetAddress local;
    private int port;
    private DatagramSocket dsocket;
    private String wakeWordDetector;

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent.getAction() != null) {
            if (intent.getAction().equals("Stop")) {
                Log.i(TAG, "Received stop ");
                stopForeground(true);
                stopSelfResult(startId);
                isActive = false;
                return START_NOT_STICKY;
            }
        }
        wakeWordDetector = intent.getStringExtra("wakeWordDetector");
        switch (wakeWordDetector) {
            case "UDP":
                try {
                    dsocket = new DatagramSocket();
                } catch (SocketException e) {
                    e.printStackTrace();
                }
                String ip = intent.getStringExtra("ip");
                port = intent.getIntExtra("port", 12101);
                try {
                    local = InetAddress.getByName(ip);
                } catch (UnknownHostException e) {
                    e.printStackTrace();
                }
        }


        createNotificationChannel();
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(this,
                0, notificationIntent, 0);

        Notification notification = new NotificationCompat.Builder(this, "Wake word")
                .setContentTitle("Wake Word")
                .setContentText("Listening for Wake Word")
                .setSmallIcon(R.drawable.app_icon)
                .setContentIntent(pendingIntent)
                .build();

        startForeground(1, notification);

        startRecorder();


        return super.onStartCommand(intent, flags, startId);
    }


    public void startRecorder() {
        Log.i(TAG, "Starting listening");
        isActive = true;
        startStreaming();
    }

    public void stopService() {
        Log.i(TAG, "Stopping the service");
        isActive = false;
        recorder.release();
        stopForeground(true);
        stopSelf();
    }

    public void pause() {
        Log.i(TAG, "pause the audio stream");
        isPaused = true;
        if (recorder != null) recorder.stop();
    }

    public void resume() {
        Log.i(TAG, "resume the audio stream");
        isPaused = false;
        if (recorder != null) recorder.startRecording();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    "Wake word",
                    "Wake word",
                    NotificationManager.IMPORTANCE_DEFAULT
            );

            NotificationManager manager = getSystemService(NotificationManager.class);
            manager.createNotificationChannel(serviceChannel);
        }
    }

    @Override
    public boolean onUnbind(Intent intent) {
        Log.i(TAG, "unbind");
        return super.onUnbind(intent);


    }

    private byte[] WaveHeader(long totalAudioLen,
                              long longSampleRate, int channels, long byteRate) {
        long totalDataLen = totalAudioLen + 36;
        byte[] header = new byte[44];
        header[0] = 'R'; // RIFF/WAVE header
        header[1] = 'I';
        header[2] = 'F';
        header[3] = 'F';
        header[4] = (byte) (totalDataLen & 0xff);
        header[5] = (byte) ((totalDataLen >> 8) & 0xff);
        header[6] = (byte) ((totalDataLen >> 16) & 0xff);
        header[7] = (byte) ((totalDataLen >> 24) & 0xff);
        header[8] = 'W';
        header[9] = 'A';
        header[10] = 'V';
        header[11] = 'E';
        header[12] = 'f'; // 'fmt ' chunk
        header[13] = 'm';
        header[14] = 't';
        header[15] = ' ';
        header[16] = 16; // 4 bytes: size of 'fmt ' chunk
        header[17] = 0;
        header[18] = 0;
        header[19] = 0;
        header[20] = 1; // format = 1
        header[21] = 0;
        header[22] = (byte) channels;
        header[23] = 0;
        header[24] = (byte) (longSampleRate & 0xff);
        header[25] = (byte) ((longSampleRate >> 8) & 0xff);
        header[26] = (byte) ((longSampleRate >> 16) & 0xff);
        header[27] = (byte) ((longSampleRate >> 24) & 0xff);
        header[28] = (byte) (byteRate & 0xff);
        header[29] = (byte) ((byteRate >> 8) & 0xff);
        header[30] = (byte) ((byteRate >> 16) & 0xff);
        header[31] = (byte) ((byteRate >> 24) & 0xff);
        header[32] = (byte) (1); // block align
        header[33] = 0;
        header[34] = 16; // bits per sample
        header[35] = 0;
        header[36] = 'd';
        header[37] = 'a';
        header[38] = 't';
        header[39] = 'a';
        header[40] = (byte) (totalAudioLen & 0xff);
        header[41] = (byte) ((totalAudioLen >> 8) & 0xff);
        header[42] = (byte) ((totalAudioLen >> 16) & 0xff);
        header[43] = (byte) ((totalAudioLen >> 24) & 0xff);
        return header;

    }

    private void startStreaming() {

        Thread streamThread = new Thread(() -> {
            try {
                int bufferSize = BUFFER_SIZE;
                byte[] buffer = new byte[bufferSize];

                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);

                recorder = new AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferSize);

                Log.d(TAG, "start recording");
                recorder.startRecording();

                while (isActive) {
                    if (isPaused) continue;

                    int result = recorder.read(buffer, 0, buffer.length);
                    if (result == AudioRecord.ERROR_BAD_VALUE || result == AudioRecord.ERROR_DEAD_OBJECT
                            || result == AudioRecord.ERROR_INVALID_OPERATION || result == AudioRecord.ERROR) {
                        recorder.stop();
                        recorder.release();
                        recorder = new AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferSize);
                        recorder.startRecording();
                        continue;

                    }
                    if (result == 0) {
                        Log.i(TAG, "Silence receiving");
                        recorder.stop();
                        recorder.startRecording();
                        continue;

                    }

                    ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
                    outputStream.write(WaveHeader(buffer.length, sampleRate, 1, byteRate));
                    outputStream.write(buffer);

                    switch (wakeWordDetector) {
                        case "UDP":
                            try {
                                DatagramPacket p = new DatagramPacket(outputStream.toByteArray(), outputStream.size(), local, port);

                                dsocket.send(p);

                            } catch (Exception e) {
                                Log.e(TAG, "Exception: " + e);
                            }
                    }

                }

                Log.d(TAG, "AudioRecord finished recording");
            } catch (Exception e) {
                Log.e(TAG, "Exception: " + e);
            }
        });

        // start the thread
        streamThread.start();
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "Destroying");
        recorder.stop();
        recorder.release();
        isActive = false;
        recorder = null;
        dsocket.close();
        super.onDestroy();
    }
}
