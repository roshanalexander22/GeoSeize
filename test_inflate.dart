import 'package:clipper2/clipper2.dart';
import 'dart:math';

void main() {
  // A path that forms a loop (e.g., user walks a square)
  final path1 = <PointD>[
    PointD(0.0, 0.0),
    PointD(100.0, 0.0),
    PointD(100.0, 100.0),
    PointD(0.0, 100.0),
    PointD(0.0, -5.0) // close the loop slightly past start
  ];

  // Inflate the path (radius = 5.0)
  final inflated = Clipper.inflatePathsD(
    paths: [path1],
    delta: 5.0,
    joinType: JoinType.round,
    endType: EndType.round,
    precision: 2,
  );

  print('Inflated paths count: \${inflated.length}');

  // Inflated will likely be a donut (2 paths: 1 outer, 1 inner hole)
  
  // To fill the hole, we use PolyTree
  final tree = Clipper.booleanOpPolyTreeD(
    clipType: ClipType.union,
    subject: inflated,
    fillRule: FillRule.nonZero,
  );

  print('PolyTree children count (outers): \${tree.count}');
  
  // Extract outers only
  final filledPaths = <PathD>[];
  for (var i = 0; i < tree.count; i++) {
    final child = tree[i];
    if (child != null && child.polygon != null) {
      filledPaths.add(child.polygon!);
    }
  }

  print('Filled paths count: \${filledPaths.length}');
  for (var p in filledPaths) {
    print('Outer Path length: \${p.length}');
  }
}
