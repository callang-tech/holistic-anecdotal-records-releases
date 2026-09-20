import 'package:flutter/material.dart';

import '../database/locations_repository.dart';
import '../models/location_selection.dart';

class LocationSelector extends StatefulWidget {
  const LocationSelector({
    super.key,
    this.initialRegionCode,
    this.initialProvinceCode,
    this.initialCityMunicipalityCode,
    this.initialBarangayCode,
    this.useDefaults = true,
    required this.onChanged,
  });

  final bool useDefaults;

  final String? initialRegionCode;
  final String? initialProvinceCode;
  final String? initialCityMunicipalityCode;
  final String? initialBarangayCode;

  final ValueChanged<LocationSelection> onChanged;

  @override
  State<LocationSelector> createState() =>
      _LocationSelectorState();
}

class _LocationSelectorState
    extends State<LocationSelector> {
  final LocationsRepository _repository =
      LocationsRepository.instance;

  List<Map<String, Object?>> _regions = [];
  List<Map<String, Object?>> _provinces = [];
  List<Map<String, Object?>> _citiesMunicipalities = [];
  List<Map<String, Object?>> _barangays = [];

  int? _regionId;
  int? _provinceId;
  int? _cityMunicipalityId;
  int? _barangayId;

  String? _regionCode;
  String? _provinceCode;
  String? _cityMunicipalityCode;
  String? _barangayCode;

  String? _regionName;
  String? _provinceName;
  String? _cityMunicipalityName;
  String? _barangayName;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final regions = await _repository.getRegions();

    if (!mounted) return;

    _regions = regions;

    // ------------------------------------------------------------
    // REGION
    // Use supplied initial value if available.
    // Otherwise default to Region II.
    // ------------------------------------------------------------
    Map<String, Object?>? region;

if (widget.initialRegionCode != null) {
  region = _findByCode(
    regions,
    widget.initialRegionCode!,
  );
}

if (region == null &&
    widget.useDefaults) {
  region = _findByName(
    regions,
    'Region II (Cagayan Valley)',
  );
}

if (region != null) {
  await _selectRegion(
    region,
    notify: false,
  );
}

if (widget.initialProvinceCode != null &&
    _regionId != null) {
  final province = _findByCode(
    _provinces,
    widget.initialProvinceCode!,
  );

  if (province != null) {
    await _selectProvince(
      province,
      notify: false,
    );
  }
} else if (widget.useDefaults &&
    _regionName == 'Region II (Cagayan Valley)') {
  final province = _findByName(
    _provinces,
    'Isabela',
  );

  if (province != null) {
    await _selectProvince(
      province,
      notify: false,
    );
  }
}

if (widget.initialCityMunicipalityCode != null) {
  final city = _findByCode(
    _citiesMunicipalities,
    widget.initialCityMunicipalityCode!,
  );

  if (city != null) {
    await _selectCityMunicipality(
      city,
      notify: false,
    );
  }
} else if (widget.useDefaults &&
    _provinceName == 'Isabela') {
  final city = _findByName(
    _citiesMunicipalities,
    'San Manuel',
  );

  if (city != null) {
    await _selectCityMunicipality(
      city,
      notify: false,
    );
  }
}

if (widget.initialBarangayCode != null) {
  final barangay = _findByCode(
    _barangays,
    widget.initialBarangayCode!,
  );

  if (barangay != null) {
    _selectBarangay(
      barangay,
      notify: false,
    );
  }
}

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    _notify();
  }

  Map<String, Object?>? _findByCode(
    List<Map<String, Object?>> items,
    String code,
  ) {
    for (final item in items) {
      if (item['psgc_code']?.toString() == code) {
        return item;
      }
    }

    return null;
  }

  Map<String, Object?>? _findByName(
    List<Map<String, Object?>> items,
    String name,
  ) {
    final target = name.trim().toLowerCase();

    for (final item in items) {
      final itemName =
          item['name']?.toString().trim().toLowerCase();

      if (itemName == target) {
        return item;
      }
    }

    return null;
  }

  Map<String, Object?>? _findById(
    List<Map<String, Object?>> items,
    int id,
  ) {
    for (final item in items) {
      if (item['id'] == id) {
        return item;
      }
    }

    return null;
  }

  Future<void> _selectRegion(
    Map<String, Object?> region, {
    required bool notify,
  }) async {
    _regionId = region['id'] as int;
    _regionCode = region['psgc_code']?.toString();
    _regionName = region['name']?.toString();

    _provinceId = null;
    _provinceCode = null;
    _provinceName = null;

    _cityMunicipalityId = null;
    _cityMunicipalityCode = null;
    _cityMunicipalityName = null;

    _barangayId = null;
    _barangayCode = null;
    _barangayName = null;

    _barangays = [];

    _provinces = await _repository.getProvinces(
      _regionId!,
    );

    if (_provinces.isEmpty) {
      _citiesMunicipalities =
          await _repository
              .getIndependentCitiesMunicipalities(
        _regionId!,
      );
    } else {
      _citiesMunicipalities = [];
    }

    if (mounted) {
      setState(() {});
    }

    if (notify) {
      _notify();
    }
  }

  Future<void> _selectProvince(
    Map<String, Object?> province, {
    required bool notify,
  }) async {
    _provinceId = province['id'] as int;
    _provinceCode =
        province['psgc_code']?.toString();
    _provinceName =
        province['name']?.toString();

    _cityMunicipalityId = null;
    _cityMunicipalityCode = null;
    _cityMunicipalityName = null;

    _barangayId = null;
    _barangayCode = null;
    _barangayName = null;

    _barangays = [];

    _citiesMunicipalities =
        await _repository.getCitiesMunicipalities(
      _provinceId!,
    );

    if (mounted) {
      setState(() {});
    }

    if (notify) {
      _notify();
    }
  }

  Future<void> _selectCityMunicipality(
    Map<String, Object?> city, {
    required bool notify,
  }) async {
    _cityMunicipalityId =
        city['id'] as int;

    _cityMunicipalityCode =
        city['psgc_code']?.toString();

    _cityMunicipalityName =
        city['name']?.toString();

    _barangayId = null;
    _barangayCode = null;
    _barangayName = null;

    _barangays =
        await _repository.getBarangays(
      _cityMunicipalityId!,
    );

    if (mounted) {
      setState(() {});
    }

    if (notify) {
      _notify();
    }
  }

  void _selectBarangay(
    Map<String, Object?> barangay, {
    required bool notify,
  }) {
    _barangayId = barangay['id'] as int;
    _barangayCode =
        barangay['psgc_code']?.toString();
    _barangayName =
        barangay['name']?.toString();

    if (mounted) {
      setState(() {});
    }

    if (notify) {
      _notify();
    }
  }

  void _notify() {
    widget.onChanged(
      LocationSelection(
        regionId: _regionId,
        regionCode: _regionCode,
        regionName: _regionName,
        provinceId: _provinceId,
        provinceCode: _provinceCode,
        provinceName: _provinceName,
        cityMunicipalityId:
            _cityMunicipalityId,
        cityMunicipalityCode:
            _cityMunicipalityCode,
        cityMunicipalityName:
            _cityMunicipalityName,
        barangayId: _barangayId,
        barangayCode: _barangayCode,
        barangayName: _barangayName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }

    final hasProvince =
        _provinces.isNotEmpty;

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _dropdown(
          label: 'Region',
          value: _regionId,
          items: _regions,
          onChanged: (id) async {
            if (id == null) {
              return;
            }

            final region = _findById(
              _regions,
              id,
            );

            if (region != null) {
              await _selectRegion(
                region,
                notify: true,
              );
            }
          },
          onClear: () {
            setState(() {
              _regionId = null;
              _regionCode = null;
              _regionName = null;

              _provinceId = null;
              _provinceCode = null;
              _provinceName = null;

              _cityMunicipalityId = null;
              _cityMunicipalityCode = null;
              _cityMunicipalityName = null;

              _barangayId = null;
              _barangayCode = null;
              _barangayName = null;

              _provinces = [];
              _citiesMunicipalities = [];
              _barangays = [];
            });

            _notify();
          },
        ),

        if (hasProvince)
          _dropdown(
            label: 'Province',
            value: _provinceId,
            items: _provinces,
            onChanged: (id) async {
              if (id == null) {
                return;
              }

              final province =
                  _findById(
                _provinces,
                id,
              );

              if (province != null) {
                await _selectProvince(
                  province,
                  notify: true,
                );
              }
            },
            onClear: () {
              setState(() {
                _provinceId = null;
                _provinceCode = null;
                _provinceName = null;

                _cityMunicipalityId = null;
                _cityMunicipalityCode = null;
                _cityMunicipalityName = null;

                _barangayId = null;
                _barangayCode = null;
                _barangayName = null;

                _citiesMunicipalities = [];
                _barangays = [];
              });

              _notify();
            },
          ),

        if (_citiesMunicipalities.isNotEmpty)
          _dropdown(
            label: 'City / Municipality',
            value: _cityMunicipalityId,
            items: _citiesMunicipalities,
            onChanged: (id) async {
              if (id == null) {
                return;
              }

              final city =
                  _findById(
                _citiesMunicipalities,
                id,
              );

              if (city != null) {
                await _selectCityMunicipality(
                  city,
                  notify: true,
                );
              }
            },
            onClear: () {
              setState(() {
                _cityMunicipalityId = null;
                _cityMunicipalityCode = null;
                _cityMunicipalityName = null;

                _barangayId = null;
                _barangayCode = null;
                _barangayName = null;

                _barangays = [];
              });

              _notify();
            },
          ),

        if (_barangays.isNotEmpty)
          _dropdown(
            label: 'Barangay',
            value: _barangayId,
            items: _barangays,
            onChanged: (id) {
              if (id == null) {
                return;
              }

              final barangay =
                  _findById(
                _barangays,
                id,
              );

              if (barangay != null) {
                _selectBarangay(
                  barangay,
                  notify: true,
                );
              }
            },
            onClear: () {
              setState(() {
                _barangayId = null;
                _barangayCode = null;
                _barangayName = null;
              });

              _notify();
            },
          ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required int? value,
    required List<Map<String, Object?>> items,
    required ValueChanged<int?> onChanged,
    VoidCallback? onClear,
  }) {
    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: value != null && onClear != null
                ? IconButton(
                    tooltip: 'Clear $label',
                    icon: const Icon(Icons.clear),
                    onPressed: onClear,
                  )
                : null,
          ),
          items: items.map((item) {
            return DropdownMenuItem<int>(
              value: item['id'] as int,
              child: Text(
                item['name']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
    );
  }
 
}
