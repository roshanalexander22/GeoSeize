import 'package:clipper2/clipper2.dart';

void main() {
  final pathD = <PointD>[
    PointD(0.0, 0.0),
    PointD(0.00001, 0.0),
    PointD(0.00002, 0.0),
    PointD(0.00001, 0.0), // Loops back
    PointD(0.0, 0.0),
  ];

  print('Inflating path...');
  try {
    final inflatedPaths = Clipper.inflatePathsD(
      paths: [pathD],
      delta: 0.000135,
      joinType: JoinType.round,
      endType: EndType.round,
      precision: 7,
    );
    print('Inflated count: ${inflatedPaths.length}');
    
    // Attempt to simplify the inflated paths to fix self-intersections
    // that cause union glitches
    // wait, we don't know the exact function signature, let's just union the path itself 
    // using a separate ClipperD instance to clean it up?
    final cleaner = ClipperD(roundingDecimalPrecision: 7);
    cleaner.addPaths(inflatedPaths, PathType.subject);
    final cleanedPathsTree = cleaner.executeTree(ClipType.union, FillRule.nonZero)?.tree ?? PolyTreeD(scale: 1);
    
    // Wait, earlier the union is exactly what produced the glitch!
    // So cleaning it with union will produce the glitch.
    
    // Let's try simplifying the original path before inflating!
    // But original path is an open path, simplifying it might not work well or we don't know how.
    
    // Instead of using EndType.round, what if we use EndType.square?
    final inflatedPathsSquare = Clipper.inflatePathsD(
      paths: [pathD],
      delta: 0.000135,
      joinType: JoinType.square,
      endType: EndType.square,
      precision: 7,
    );
    
    final clipperSq = ClipperD(roundingDecimalPrecision: 7);
    clipperSq.addPaths(inflatedPathsSquare, PathType.subject);
    final unionTreeSq = clipperSq.executeTree(ClipType.union, FillRule.nonZero)?.tree ?? PolyTreeD(scale: 1);
    
    // Try manually unscaling
    print('Union tree children (Square): ${unionTreeSq.children.length}');
    for (var child in unionTreeSq.children) {
      if (child.polygon != null) {
        print('Child poly size: ${child.polygon!.length}');
        for (var pt in child.polygon!) {
          double unscaledY = pt.y / 100000000000000.0;
          if (unscaledY > 90 || unscaledY < -90) {
            print('GLITCH from union: $unscaledY');
          } else {
            print('Valid: $unscaledY');
            break;
          }
        }
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
