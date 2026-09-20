class LocationSelection {
  const LocationSelection({
    this.regionId,
    this.regionCode,
    this.regionName,
    this.provinceId,
    this.provinceCode,
    this.provinceName,
    this.cityMunicipalityId,
    this.cityMunicipalityCode,
    this.cityMunicipalityName,
    this.barangayId,
    this.barangayCode,
    this.barangayName,
  });

  final int? regionId;
  final String? regionCode;
  final String? regionName;

  final int? provinceId;
  final String? provinceCode;
  final String? provinceName;

  final int? cityMunicipalityId;
  final String? cityMunicipalityCode;
  final String? cityMunicipalityName;

  final int? barangayId;
  final String? barangayCode;
  final String? barangayName;
}