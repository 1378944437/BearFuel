import 'dart:math';

/// A small local projection used by the lightweight station map.
///
/// The map is not backed by a tile provider, so its screen coordinates must
/// use the same projection when drawing markers and converting a drag back to
/// a geographic coordinate.
class MapCoordinate {
  final double latitude;
  final double longitude;

  const MapCoordinate({required this.latitude, required this.longitude});
}

class LocalMapProjection {
  // Keep the existing vertical zoom while deriving the horizontal scale from
  // the physical length of a longitude degree at the map latitude.
  static const double pixelsPerLatitudeDegree = 4500.0;

  static double pixelsPerLongitudeDegree(double latitude) {
    return pixelsPerLatitudeDegree * cos(latitude * pi / 180.0);
  }

  static double xForCoordinate({
    required double latitude,
    required double longitude,
    required double centerLatitude,
    required double centerLongitude,
  }) {
    return (longitude - centerLongitude) *
        pixelsPerLongitudeDegree(centerLatitude);
  }

  static double yForCoordinate({
    required double latitude,
    required double centerLatitude,
  }) {
    return (centerLatitude - latitude) * pixelsPerLatitudeDegree;
  }

  /// Returns the coordinate at the fixed screen center after a map drag.
  static MapCoordinate centerForPan({
    required double centerLatitude,
    required double centerLongitude,
    required double panX,
    required double panY,
  }) {
    return MapCoordinate(
      // A positive screen Y drag moves the map north, so the screen center is
      // now north of the original center.
      latitude: centerLatitude + panY / pixelsPerLatitudeDegree,
      // A positive screen X drag moves the map east, so the screen center is
      // now west of the original center.
      longitude:
          centerLongitude - panX / pixelsPerLongitudeDegree(centerLatitude),
    );
  }
}
