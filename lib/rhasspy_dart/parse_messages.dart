class AsrTextCaptured {
  String text;
  double likelihood;
  double seconds;
  String siteId;
  String sessionId;
  String wakewordId;

  AsrTextCaptured(
      {this.text,
      this.likelihood,
      this.seconds,
      this.siteId,
      this.sessionId,
      this.wakewordId});

  AsrTextCaptured.fromJson(Map<String, dynamic> json) {
    text = json['text'];
    if (json['likelihood'] is double) {
      likelihood = json['likelihood'];
    } else {
      likelihood = double.parse(json['likelihood'].toString());
    }
    if (json['seconds'] is double) {
      seconds = json['seconds'];
    } else {
      seconds = double.parse(json['seconds'].toString());
    }

    siteId = json['siteId'];
    sessionId = json['sessionId'];
    wakewordId = json['wakewordId'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['text'] = this.text;
    data['likelihood'] = this.likelihood;
    data['seconds'] = this.seconds;
    data['siteId'] = this.siteId;
    data['sessionId'] = this.sessionId;
    data['wakewordId'] = this.wakewordId;
    return data;
  }
}

class NluIntentParsed {
  String input;
  Intent intent;
  String siteId;
  String id;
  List<Slots> slots;
  String sessionId;

  NluIntentParsed(
      {this.input,
      this.intent,
      this.siteId,
      this.id,
      this.slots,
      this.sessionId});

  NluIntentParsed.fromJson(Map<String, dynamic> json) {
    input = json['input'];
    intent =
        json['intent'] != null ? new Intent.fromJson(json['intent']) : null;
    siteId = json['siteId'];
    id = json['id'];
    if (json['slots'] != null) {
      slots = new List<Slots>();
      json['slots'].forEach((v) {
        slots.add(new Slots.fromJson(v));
      });
    }
    sessionId = json['sessionId'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['input'] = this.input;
    if (this.intent != null) {
      data['intent'] = this.intent.toJson();
    }
    data['siteId'] = this.siteId;
    data['id'] = this.id;
    if (this.slots != null) {
      data['slots'] = this.slots.map((v) => v.toJson()).toList();
    }
    data['sessionId'] = this.sessionId;
    return data;
  }
}

class Intent {
  String intentName;
  double confidenceScore;

  Intent({this.intentName, this.confidenceScore});

  Intent.fromJson(Map<String, dynamic> json) {
    intentName = json['intentName'];
    confidenceScore = json['confidenceScore'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['intentName'] = this.intentName;
    data['confidenceScore'] = this.confidenceScore;
    return data;
  }
}

class Slots {
  String entity;
  Value value;
  String slotName;
  String rawValue;
  double confidence;
  Range range;

  Slots(
      {this.entity,
      this.value,
      this.slotName,
      this.rawValue,
      this.confidence,
      this.range});

  Slots.fromJson(Map<String, dynamic> json) {
    entity = json['entity'];
    value = json['value'] != null ? new Value.fromJson(json['value']) : null;
    slotName = json['slotName'];
    rawValue = json['rawValue'];
    confidence = json['confidence'];
    range = json['range'] != null ? new Range.fromJson(json['range']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['entity'] = this.entity;
    if (this.value != null) {
      data['value'] = this.value.toJson();
    }
    data['slotName'] = this.slotName;
    data['rawValue'] = this.rawValue;
    data['confidence'] = this.confidence;
    if (this.range != null) {
      data['range'] = this.range.toJson();
    }
    return data;
  }
}

class Value {
  String kind;
  String value;

  Value({this.kind, this.value});

  Value.fromJson(Map<String, dynamic> json) {
    kind = json['kind'];
    value = json['value'].toString();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['kind'] = this.kind;
    data['value'] = this.value;
    return data;
  }
}

class Range {
  int start;
  int end;
  int rawStart;
  int rawEnd;

  Range({this.start, this.end, this.rawStart, this.rawEnd});

  Range.fromJson(Map<String, dynamic> json) {
    start = json['start'];
    end = json['end'];
    rawStart = json['rawStart'];
    rawEnd = json['rawEnd'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['start'] = this.start;
    data['end'] = this.end;
    data['rawStart'] = this.rawStart;
    data['rawEnd'] = this.rawEnd;
    return data;
  }
}

class DialogueEndSession {
  String sessionId;
  String text;
  String customData;

  DialogueEndSession({this.sessionId, this.text, this.customData});

  DialogueEndSession.fromJson(Map<String, dynamic> json) {
    sessionId = json['sessionId'];
    text = json['text'];
    customData = json['customData'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['sessionId'] = this.sessionId;
    data['text'] = this.text;
    data['customData'] = this.customData;
    return data;
  }
}

class DialogueContinueSession {
  String sessionId;
  String customData;
  String text;
  List<String> intentFilter;
  bool sendIntentNotRecognized;
  List<Slots> slot;
  String lang;

  DialogueContinueSession(
      {this.sessionId,
      this.customData,
      this.text,
      this.intentFilter,
      this.sendIntentNotRecognized,
      this.slot,
      this.lang});

  DialogueContinueSession.fromJson(Map<String, dynamic> json) {
    sessionId = json['sessionId'];
    customData = json['customData'];
    text = json['text'];
    if (json['intentFilter'] != null)
      intentFilter = json['intentFilter'].cast<String>();
    sendIntentNotRecognized = json['sendIntentNotRecognized'];
    if (json['slots'] != null) {
      slot = new List<Slots>();
      json['slots'].forEach((v) {
        slot.add(new Slots.fromJson(v));
      });
    }
    lang = json['lang'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['sessionId'] = this.sessionId;
    data['customData'] = this.customData;
    data['text'] = this.text;
    data['intentFilter'] = this.intentFilter;
    data['sendIntentNotRecognized'] = this.sendIntentNotRecognized;
    data['slot'] = this.slot;
    data['lang'] = this.lang;
    return data;
  }
}

class DialogueStartSession {
  String siteId;
  String customData;
  Init init;

  DialogueStartSession({this.siteId, this.customData, this.init});

  DialogueStartSession.fromJson(Map<String, dynamic> json) {
    siteId = json['siteId'];
    customData = json['customData'];
    init = json['init'] != null ? new Init.fromJson(json['init']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['siteId'] = this.siteId;
    data['customData'] = this.customData;
    if (this.init != null) {
      data['init'] = this.init.toJson();
    }
    return data;
  }
}

class Init {
  String type;
  String text;
  bool canBeEnqueued;
  List<String> intentFilter;

  Init({this.type, this.text, this.canBeEnqueued, this.intentFilter});

  Init.fromJson(Map<String, dynamic> json) {
    type = json['type'];
    text = json['text'];
    canBeEnqueued = json['canBeEnqueued'];
    if (intentFilter != null)
      intentFilter = json['intentFilter'].cast<String>();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['type'] = this.type;
    data['text'] = this.text;
    data['canBeEnqueued'] = this.canBeEnqueued;
    data['intentFilter'] = this.intentFilter;
    return data;
  }
}

class DialogueSessionStarted {
  String sessionId;
  String siteId;
  String customData;
  String lang;

  DialogueSessionStarted(
      {this.sessionId, this.siteId, this.customData, this.lang});

  DialogueSessionStarted.fromJson(Map<String, dynamic> json) {
    sessionId = json['sessionId'];
    siteId = json['siteId'];
    customData = json['customData'];
    lang = json['lang'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['sessionId'] = this.sessionId;
    data['siteId'] = this.siteId;
    data['customData'] = this.customData;
    data['lang'] = this.lang;
    return data;
  }
}

class DialogueSessionEnded {
  Termination termination;
  String sessionId;
  String siteId;
  String customData;

  DialogueSessionEnded(
      {this.termination, this.sessionId, this.siteId, this.customData});

  DialogueSessionEnded.fromJson(Map<String, dynamic> json) {
    termination = json['termination'] != null
        ? new Termination.fromJson(json['termination'])
        : null;
    sessionId = json['sessionId'];
    siteId = json['siteId'];
    customData = json['customData'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.termination != null) {
      data['termination'] = this.termination.toJson();
    }
    data['sessionId'] = this.sessionId;
    data['siteId'] = this.siteId;
    data['customData'] = this.customData;
    return data;
  }
}

class Termination {
  String reason;

  Termination({this.reason});

  Termination.fromJson(Map<String, dynamic> json) {
    reason = json['reason'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['reason'] = this.reason;
    return data;
  }
}

class NluIntentNotRecognized {
  String input;
  String siteId;
  String id;
  String customData;
  String sessionId;

  NluIntentNotRecognized(
      {this.input, this.siteId, this.id, this.customData, this.sessionId});

  NluIntentNotRecognized.fromJson(Map<String, dynamic> json) {
    input = json['input'];
    siteId = json['siteId'];
    id = json['id'];
    customData = json['customData'];
    sessionId = json['sessionId'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['input'] = this.input;
    data['siteId'] = this.siteId;
    data['id'] = this.id;
    data['customData'] = this.customData;
    data['sessionId'] = this.sessionId;
    return data;
  }
}

class HotwordDetected {
  String modelId;
  String modelVersion;
  String modelType;
  double currentSensitivity;
  String siteId;
  String sessionId;
  bool sendAudioCaptured;
  String lang;

  HotwordDetected(
      {this.modelId,
      this.modelVersion,
      this.modelType,
      this.currentSensitivity,
      this.siteId,
      this.sessionId,
      this.sendAudioCaptured,
      this.lang});

  HotwordDetected.fromJson(Map<String, dynamic> json) {
    modelId = json['modelId'];
    modelVersion = json['modelVersion'];
    modelType = json['modelType'];
    currentSensitivity = json['currentSensitivity'];
    siteId = json['siteId'];
    sessionId = json['sessionId'];
    sendAudioCaptured = json['sendAudioCaptured'];
    lang = json['lang'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['modelId'] = this.modelId;
    data['modelVersion'] = this.modelVersion;
    data['modelType'] = this.modelType;
    data['currentSensitivity'] = this.currentSensitivity;
    data['siteId'] = this.siteId;
    data['sessionId'] = this.sessionId;
    data['sendAudioCaptured'] = this.sendAudioCaptured;
    data['lang'] = this.lang;
    return data;
  }
}

class HotwordToggle {
  String siteId;
  String reason;

  HotwordToggle({this.siteId, this.reason});

  HotwordToggle.fromJson(Map<String, dynamic> json) {
    siteId = json['siteId'];
    reason = json['reason'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['siteId'] = this.siteId;
    data['reason'] = this.reason;
    return data;
  }
}

class AudioSetVolume {
  double volume;
  String siteId;

  AudioSetVolume({this.volume, this.siteId});

  AudioSetVolume.fromJson(Map<String, dynamic> json) {
    volume = json['volume'];
    siteId = json['siteId'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['volume'] = this.volume;
    data['siteId'] = this.siteId;
    return data;
  }
}
