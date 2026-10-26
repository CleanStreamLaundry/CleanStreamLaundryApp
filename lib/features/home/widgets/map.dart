import 'package:clean_stream_laundry_app/logic/parsing/location_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LocationMap extends StatefulWidget {
  static const LatLng _defaultCenter = LatLng(40.273502, -86.126976);

  final List<Map<String, dynamic>> locations;
  final MapController mapController;
  final LatLng? selectedLocation;
  final double? height;

  const LocationMap({
    super.key,
    required this.locations,
    required this.mapController,
    this.selectedLocation,
    this.height = 300,
  });

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  @override
  void initState() {
    super.initState();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLocation == widget.selectedLocation) return;
    _syncSelection();
  }

  void _syncSelection() {
    // Resize events must finish first or they prune tiles using the old camera.
    final selected = widget.selectedLocation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.microtask(() {
        if (!mounted || widget.selectedLocation != selected) return;
        widget.mapController.move(
          selected ?? LocationMap._defaultCenter,
          selected == null ? 7.2 : 15,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final markers = LocationParser.parseLocations(widget.locations);
    final initialCenter = widget.selectedLocation ?? LocationMap._defaultCenter;

    return Card(
      elevation: 5,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.20)),
      ),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: FlutterMap(
          mapController: widget.mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: widget.selectedLocation == null ? 7.2 : 15,
            keepAlive: true,
            maxZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'https://cleanstreamlaundry.com/',
              tileProvider: NetworkTileProvider(),
            ),
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }
}
