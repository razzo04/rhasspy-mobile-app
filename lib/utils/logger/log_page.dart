import 'logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

void openLogPage(BuildContext context, Logger logger) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => LogPage(
        logger: logger,
      ),
    ),
  );
}

class LogPage extends StatefulWidget {
  final Logger logger;
  final double textSize;
  LogPage({Key key, this.logger, this.textSize = 20}) : super(key: key);

  @override
  _LogPageState createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  MemoryLogOutput memoryOutput;
  FileOutput fileOutput;
  DateFormat formatter = DateFormat.Hms();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Log"),
        actions: [
          Tooltip(
            message: "Copy log to clipBoard",
            child: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                String text = "";
                if (fileOutput != null) {
                  fileOutput.readLogs().forEach((line) {
                    text += "$line\n";
                  });
                } else {
                  SimplePrinter printer =
                      SimplePrinter(includeStackTrace: true);
                  printer.init();
                  for (var log in memoryOutput.buffer) {
                    printer.log(log).forEach((line) {
                      text += line;
                    });
                  }
                }
                Clipboard.setData(ClipboardData(text: text));
              },
            ),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: ListView.builder(
        itemBuilder: (context, index) {
          LogMessage logMessage = memoryOutput.buffer.elementAt(index);
          return Card(
            elevation: 5,
            color: levelToColor(logMessage.logLevel),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 5, right: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (logMessage.title != null)
                        Text(
                          logMessage.title,
                          style: TextStyle(fontSize: widget.textSize),
                        ),
                      if (logMessage.time != null)
                        Text(
                          formatter.format(logMessage.time),
                          style: TextStyle(fontSize: widget.textSize),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  child: Text(
                    logMessage.message,
                    textAlign: TextAlign.left,
                    style: TextStyle(fontSize: widget.textSize - 5),
                  ),
                ),
                if (logMessage.stackTrace != null)
                  //TODO fix set state when animation is in progress
                  StackTraceWidget(
                    logMessage.stackTrace,
                    duration: const Duration(milliseconds: 400),
                  )
                else
                  SizedBox(
                    width: 10,
                    height: 10,
                  )
              ],
            ),
          );
        },
        itemCount: memoryOutput.buffer.length,
      ),
    );
  }

  @override
  void initState() {
    if (widget.logger.logOutput is MemoryLogOutput) {
      memoryOutput = widget.logger.logOutput;
    } else if (widget.logger.logOutput is MultiOutput) {
      for (var logOuput
          in (widget.logger.logOutput as MultiOutput).logOutputs) {
        if (logOuput is MemoryLogOutput) {
          memoryOutput = logOuput;
          break;
        } else if (logOuput is FileOutput) {
          fileOutput = logOuput;
        }
      }
    }
    memoryOutput.onUpdate = () {
      setState(() {});
    };
    super.initState();
  }

  @override
  void dispose() {
    memoryOutput.onUpdate = () {};
    super.dispose();
  }

  Color levelToColor(Level level) {
    switch (level) {
      case Level.verbose:
        return Colors.lightBlue;
        break;
      case Level.debug:
        return Colors.cyan;
        break;
      case Level.info:
        return Colors.green;
        break;
      case Level.warning:
        return Colors.orange;
        break;
      case Level.error:
        return Colors.red;
        break;
      case Level.critical:
        return Colors.redAccent[700];
        break;
    }
  }
}

class StackTraceWidget extends StatefulWidget {
  final Duration duration;
  final StackTrace stackTrace;
  final bool defaultOpen;
  StackTraceWidget(this.stackTrace,
      {Key key,
      this.duration = const Duration(milliseconds: 250),
      this.defaultOpen = false})
      : super(key: key);

  @override
  _StackTraceWidgetState createState() => _StackTraceWidgetState();
}

class _StackTraceWidgetState extends State<StackTraceWidget>
    with SingleTickerProviderStateMixin {
  bool isStackTraceVisible = false;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSize(
          vsync: this,
          curve: Curves.easeIn,
          duration: widget.duration,
          child: Container(
            child:
                isStackTraceVisible ? Text(widget.stackTrace.toString()) : null,
          ),
        ),
        Center(
          child: AnimationRotationIconButton(
            duration: widget.duration,
            onPressed: () {
              setState(() {
                isStackTraceVisible = !isStackTraceVisible;
              });
            },
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    isStackTraceVisible = widget.defaultOpen;
    super.initState();
  }
}

class AnimationRotationIconButton extends StatefulWidget {
  final double startAngle;
  final double endAngle;
  final Duration duration;
  final Icon icon;
  final void Function() onPressed;
  AnimationRotationIconButton(
      {Key key,
      this.startAngle = 0,
      this.endAngle = 3.14,
      this.duration = const Duration(milliseconds: 250),
      this.icon = const Icon(Icons.arrow_drop_down),
      this.onPressed})
      : super(key: key);

  @override
  _AnimationRotationIconButtonState createState() =>
      _AnimationRotationIconButtonState();
}

class _AnimationRotationIconButtonState
    extends State<AnimationRotationIconButton> {
  double startAngle = 0;
  double endAngle = 0;
  bool isInStartCondition = true;
  @override
  Widget build(BuildContext context) {
    return Container(
      child: TweenAnimationBuilder(
        duration: widget.duration,
        curve: Curves.easeIn,
        tween: Tween<double>(begin: startAngle, end: endAngle),
        child: widget.icon,
        builder: (BuildContext context, double size, Widget child) {
          return Transform.rotate(
            angle: size,
            child: IconButton(
              icon: child,
              onPressed: () {
                setState(() {
                  if (isInStartCondition) {
                    startAngle = widget.startAngle;
                    endAngle = widget.endAngle;
                    isInStartCondition = false;
                  } else {
                    endAngle = widget.startAngle;
                    startAngle = widget.endAngle;
                    isInStartCondition = true;
                  }
                });
                if (widget.onPressed != null) widget.onPressed();
              },
              iconSize: 32,
            ),
          );
        },
      ),
    );
  }
}
