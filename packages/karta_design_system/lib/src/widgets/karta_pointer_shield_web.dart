import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Official Flutter Web platform-view pointer interception pattern:
/// places an invisible (`isVisible: false`) `div` behind [child] in DOM stacking
/// order above lower platform views (MapLibre GL canvas). Events over [child]
/// hit this barrier instead of the map canvas, while bubbling cleanly into
/// Flutter's pointer arena and preserving `TextField` input focus.
Widget buildPointerShield({required Widget child}) {
  return Stack(
    fit: StackFit.passthrough,
    alignment: Alignment.center,
    children: <Widget>[
      Positioned.fill(
        child: HtmlElementView.fromTagName(
          tagName: 'div',
          isVisible: false,
          onElementCreated: (Object element) {
            final el = element as web.HTMLElement;
            el.style
              ..width = '100%'
              ..height = '100%'
              ..pointerEvents = 'auto';
            // Prevent default mousedown focus shift so Flutter TextField inputs
            // inside overlaid panels keep focus cleanly across clicks.
            el.addEventListener(
              'mousedown',
              (web.Event event) {
                event.preventDefault();
              }.toJS,
            );
          },
        ),
      ),
      child,
    ],
  );
}
