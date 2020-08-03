import 'package:flutter/material.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/parse_messages.dart';

class IntentViewer extends StatefulWidget {
  final NluIntentParsed intent;
  IntentViewer(this.intent, {Key key}) : super(key: key);

  @override
  _IntentViewerState createState() => _IntentViewerState();
}

class _IntentViewerState extends State<IntentViewer> {
  @override
  Widget build(BuildContext context) {
    if (widget.intent != null) {
      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
                decoration: BoxDecoration(
                    color: Colors.blue,
                    border: Border.all(width: 0.5),
                    borderRadius: BorderRadius.circular(5)),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    widget.intent.intent.intentName,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                    textScaleFactor: 1.5,
                  ),
                )),
          ),
          ListView.builder(
            itemBuilder: (context, index) {
              Slots slot = widget.intent.slots.elementAt(index);
              // Text.rich(textSpan)
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        slot.value.value,
                        textScaleFactor: 1.1,
                        style: TextStyle(),
                      ),
                    ),
                    Container(
                        // color: Colors.red,
                        decoration: BoxDecoration(
                            color: Colors.blue,
                            border: Border.all(width: 0.5),
                            borderRadius: BorderRadius.circular(5)),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Text(
                            slot.slotName,
                            style: TextStyle(
                              color: Colors.white,
                            ),
                            textScaleFactor: 1.5,
                          ),
                        )),
                  ],
                ),
              );
            },
            itemCount: widget.intent.slots.length,
            physics: NeverScrollableScrollPhysics(),
            shrinkWrap: true,
          ),
        ],
      );
    }
    return Container();
  }
}
