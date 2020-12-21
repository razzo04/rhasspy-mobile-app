// This file is based on work covered by the following copyright and permission notice:

// MIT License

// Copyright (c) 2019 Simon Leier

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// If you want to get a logger which prints beautiful logs please visit https://github.com/leisim/logger.
// This version includes the necessary changes for creating a nice flutter log page.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// [Level]s to control logging output. Logging can be enabled to include all
/// levels above certain [Level].
enum Level {
  verbose,
  debug,
  info,
  warning,
  error,
  critical,
}

class LogMessage {
  String message;
  Level logLevel;
  StackTrace stackTrace;
  DateTime time;
  String title;
  LogMessage(
      {this.message, this.logLevel, this.stackTrace, this.time, this.title});
}

abstract class LogOutput {
  void init() {}

  void output(LogMessage event);

  void dispose() {}
}

abstract class LogPrinter {
  void init() {}

  List<String> log(LogMessage event);

  void destroy() {}
}

class MultiOutput implements LogOutput {
  List<LogOutput> logOutputs;
  MultiOutput(this.logOutputs);
  @override
  void dispose() {
    logOutputs.forEach((logOutput) {
      logOutput.dispose();
    });
  }

  @override
  void init() {
    logOutputs.forEach((logOutput) {
      logOutput.init();
    });
  }

  @override
  void output(LogMessage event) {
    logOutputs.forEach((logOutput) {
      logOutput.output(event);
    });
  }
}

class SimplePrinter implements LogPrinter {
  static final levelPrefixes = {
    Level.verbose: '[V]',
    Level.debug: '[D]',
    Level.info: '[I]',
    Level.warning: '[W]',
    Level.error: '[E]',
    Level.critical: '[C]',
  };
  final bool includeStackTrace;
  const SimplePrinter({this.includeStackTrace = true});

  @override
  List<String> log(LogMessage event) {
    var messageStr = _stringifyMessage(event.message);
    var errorStr = event.title != null ? ' TAG: ${event.title}' : '';
    var timeStr =
        event.time != null ? 'TIME: ${event.time.toIso8601String()}' : '';
    var stackStrace = event.stackTrace != null && this.includeStackTrace
        ? event.stackTrace.toString()
        : '';
    return [
      '${levelPrefixes[event.logLevel]} $timeStr $messageStr$errorStr\n$stackStrace'
    ];
  }

  String _stringifyMessage(dynamic message) {
    if (message is Map || message is Iterable) {
      var encoder = JsonEncoder.withIndent(null);
      return encoder.convert(message);
    } else {
      return message.toString();
    }
  }

  @override
  void destroy() {}

  @override
  void init() {}
}

class FileOutput extends LogOutput {
  final File file;
  final bool overrideExisting;
  final Encoding encoding;
  final LogPrinter printer;
  IOSink _sink;

  FileOutput(
      {this.file,
      this.overrideExisting = false,
      this.encoding = utf8,
      this.printer = const SimplePrinter()});

  @override
  void init() {
    _sink = file.openWrite(
      mode: overrideExisting ? FileMode.writeOnly : FileMode.writeOnlyAppend,
      encoding: encoding,
    );
  }

  @override
  void output(LogMessage event) {
    printer.log(event).forEach((line) => _sink.write(line));
  }

  @override
  void dispose() async {
    await _sink.flush();
    await _sink.close();
  }

  List<String> readLogs() {
    return file.readAsLinesSync(encoding: encoding);
  }
}

class MemoryLogOutput implements LogOutput {
  /// Maximum events in [buffer].
  final int bufferSize;

  /// The buffer of events.
  final ListQueue<LogMessage> buffer;

  void Function() onUpdate;

  MemoryLogOutput({this.bufferSize = 40}) : buffer = ListQueue(bufferSize);

  @override
  void output(LogMessage event) {
    if (buffer.length == bufferSize) {
      buffer.removeFirst();
    }
    buffer.add(event);
    if (onUpdate != null) onUpdate();
  }

  @override
  void dispose() {
    buffer.clear();
  }

  @override
  void init() {}
}

class StreamLogOutput implements LogOutput {
  StreamController<LogMessage> _streamLog = StreamController.broadcast();
  Stream<LogMessage> get stream => _streamLog.stream;
  @override
  void dispose() {
    _streamLog.close();
    _streamLog = null;
  }

  @override
  void init() {}

  @override
  void output(LogMessage event) {
    _streamLog.add(event);
  }
}

class ConsoleOutput implements LogOutput {
  @override
  void dispose() {}
  final LogPrinter printer;
  ConsoleOutput({this.printer = const SimplePrinter()});
  @override
  void init() {}

  @override
  void output(LogMessage event) {
    printer.log(event).forEach(print);
  }
}

class Logger {
  Level level = Level.verbose;
  LogOutput logOutput;
  Logger({this.logOutput}) {
    logOutput ??= ConsoleOutput();
    logOutput.init();
  }

  /// Log a message at level [Level.verbose].
  void v(dynamic message, [dynamic tag, StackTrace stackTrace]) {
    log(Level.verbose, message,
        tag: tag, stackTrace: stackTrace, includeTime: true);
  }

  /// Log a message at level [Level.debug].
  void d(dynamic message, [dynamic tag, StackTrace stackTrace]) {
    log(Level.debug, message,
        tag: tag, stackTrace: stackTrace, includeTime: true);
  }

  /// Log a message at level [Level.info].
  void i(dynamic message, [dynamic tag, StackTrace stackTrace]) {
    log(Level.info, message,
        tag: tag, stackTrace: stackTrace, includeTime: true);
  }

  /// Log a message at level [Level.warning].
  void w(dynamic message, [dynamic tag, StackTrace stackTrace]) {
    log(Level.warning, message,
        tag: tag, stackTrace: stackTrace, includeTime: true);
  }

  /// Log a message at level [Level.error].
  void e(dynamic message, [dynamic tag, StackTrace stackTrace]) {
    log(Level.error, message,
        tag: tag, stackTrace: stackTrace, includeTime: true);
  }

  /// Log a message at level [Level.critical].
  void critical(dynamic message, [dynamic tag, StackTrace stackTrace]) {
    log(Level.critical, message,
        tag: tag, stackTrace: stackTrace, includeTime: true);
  }

  /// Log a message with [level].
  void log(Level level, dynamic message,
      {String tag, StackTrace stackTrace, bool includeTime = false}) {
    LogMessage logMessage = LogMessage();
    if (includeTime) {
      logMessage.time = DateTime.now();
    }
    logMessage.message = message;
    logMessage.stackTrace = stackTrace;
    logMessage.logLevel = level;
    logMessage.title = tag;
    logOutput.output(logMessage);
  }

  void dispose() {
    logOutput.dispose();
  }
}
