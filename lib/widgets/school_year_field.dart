import 'package:flutter/material.dart';
import '../models/school_year.dart';

class SchoolYearField extends StatelessWidget {
  const SchoolYearField(
      {super.key,
      required this.controller,
      this.onChanged,
      this.label = 'School Year *'});
  final TextEditingController controller;
  final VoidCallback? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: ValueKey(controller.text),
        initialValue: controller.text,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: SchoolYear.options(stored: controller.text)
            .map((year) => DropdownMenuItem(
                value: year,
                child: Text(year.isEmpty ? 'Not specified' : year)))
            .toList(),
        onChanged: (value) {
          if (value == null || value == controller.text) return;
          controller.text = value;
          onChanged?.call();
        },
      );
}
