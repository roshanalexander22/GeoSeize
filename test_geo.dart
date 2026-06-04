import 'package:latlong2/latlong.dart';
import 'lib/utils/geo_calculator.dart';
import 'package:clipper2/clipper2.dart';

void main() {
  final path = <LatLng>[
    LatLng(10.00000, 10.00000),
    LatLng(10.00010, 10.00000),
    LatLng(10.00010, 10.00010),
    LatLng(10.00000, 10.00010),
    LatLng(10.00000, 10.00000)
  ];

  final pathD = <PointD>[];
  for (var p in path) {
    pathD.add(PointD(p.longitude, p.latitude));
  }

  final inflatedPaths = Clipper.inflatePathsD(
    paths: [pathD],
    delta: 0.000135,
    joinType: JoinType.round,
    endType: EndType.round,
    precision: 7,
  );

  print('Inflated paths count: ' + inflatedPaths.length.toString());

  final clipper = ClipperD(roundingDecimalPrecision: 7);
  clipper.addPaths(inflatedPaths, PathType.subject);
  final tree = clipper.executeTree(ClipType.union, FillRule.nonZero)?.tree ?? PolyTreeD(scale: pow(10, 7).toDouble());

  print('PolyTree root children count (precision 7): ' + tree.children.length.toString());
  
  if (tree.children.isNotEmpty) {
    final firstChild = tree.children.first;
    print('First child length: ' + firstChild.polygon!.length.toString());
  }
}
