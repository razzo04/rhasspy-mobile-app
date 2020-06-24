import 'package:json_annotation/json_annotation.dart';

part 'HermesTextCaptured.g.dart';
@JsonSerializable()

class HermesTextCaptured {
  HermesTextCaptured(this.text, this.likelihood, this.seconds, this.siteId, this.sessionId,this.wakeWordId);
  String text;
  double likelihood;
  double seconds;
  String siteId;
  String sessionId;
  String wakeWordId;
  factory HermesTextCaptured.fromJson(Map<String, dynamic> json) => _$HermesTextCapturedFromJson(json);

  Map<String, dynamic> toJson() => _$HermesTextCapturedToJson(this);
  
}