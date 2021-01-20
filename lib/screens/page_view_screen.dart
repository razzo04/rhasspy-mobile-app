import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:rhasspy_mobile_app/screens/app_settings.dart';
import 'package:rhasspy_mobile_app/screens/home_page.dart';

class PageViewScreen extends StatefulWidget {
  PageViewScreen({Key key}) : super(key: key);

  @override
  _PageViewScreenState createState() => _PageViewScreenState();
}

class _PageViewScreenState extends State<PageViewScreen> {
  PageController _controller = PageController(initialPage: 0);
  List<Widget> _children = [HomePage(), AppSettings()];
  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      itemBuilder: (context, index) {
        return _children[index % _children.length];
      },
      scrollDirection: Axis.horizontal,
      controller: _controller,
      onPageChanged: (value) {},
    );
  }
}
