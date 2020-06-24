// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'HermesTextCaptured.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HermesTextCaptured _$HermesTextCapturedFromJson(Map<String, dynamic> json) {
  return HermesTextCaptured(
    json['text'] as String,
    (json['likelihood'] as num)?.toDouble(),
    (json['seconds'] as num)?.toDouble(),
    json['siteId'] as String,
    json['sessionId'] as String,
    json['wakeWordId'] as String,
  );
}

Map<String, dynamic> _$HermesTextCapturedToJson(HermesTextCaptured instance) =>
    <String, dynamic>{
      'text': instance.text,
      'likelihood': instance.likelihood,
      'seconds': instance.seconds,
      'siteId': instance.siteId,
      'sessionId': instance.sessionId,
      'wakeWordId': instance.wakeWordId,
    };
