import 'package:clipper2/clipper2.dart';

void main() {
  final path1 = <PointD>[
    PointD(0.0, 0.0),
    PointD(10.0, 0.0),
    PointD(10.0, 10.0),
    PointD(0.0, 10.0)
  ];

  final path2 = <PointD>[
    PointD(5.0, 5.0),
    PointD(15.0, 5.0),
    PointD(15.0, 15.0),
    PointD(5.0, 15.0)
  ];

  final subj = <PathD>[path1];
  final clip = <PathD>[path2];

  final solution = Clipper.unionD(subject: subj, clip: clip, fillRule: FillRule.nonZero);
  
  print('Solution paths: \${solution.length}');
  for (var p in solution) {
    print('Path length: \${p.length}');
    for (var pt in p) {
      print('\${pt.x}, \${pt.y}');
    }
  }

  // Test point in polygon
  final isInside = path1.pointInPolygon(PointD(5.0, 5.0));
  print('Is 5,5 inside path1: \$isInside');
}
