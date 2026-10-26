import '../widgets/location_selector.dart';
import '../controller.dart';
import 'package:clean_stream_laundry_app/core/theme/theme.dart';
import 'package:flutter/material.dart';

class MaintenanceForm extends StatelessWidget {
  final MaintenanceController controller;

  const MaintenanceForm({super.key, required this.controller});

  InputDecoration _inputDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintMaxLines: 3,
      errorMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.fontSecondary, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.fontSecondary, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a Category',
          style: TextStyle(
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: colorScheme.fontInverted,
          ),
        ),
        const SizedBox(height: 4),

        DropdownButtonFormField<String>(
          initialValue: controller.selectedCategory,
          isExpanded: true,
          itemHeight: null,
          decoration: _inputDecoration(context),
          dropdownColor: Theme.of(context).colorScheme.surface,
          iconEnabledColor: colorScheme.fontSecondary,
          style: TextStyle(letterSpacing: 0, color: colorScheme.fontInverted),
          hint: Text(
            'Select a category',
            style: TextStyle(
              letterSpacing: 0,
              color: colorScheme.fontSecondary,
            ),
          ),

          items: controller.categories
              .map(
                (cat) => DropdownMenuItem(
                  value: cat,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(cat),
                  ),
                ),
              )
              .toList(),

          onChanged: (value) {
            controller.selectCategory(value!);
          },
        ),

        const SizedBox(height: 18),

        Text(
          'Location',
          style: TextStyle(
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: colorScheme.fontInverted,
          ),
        ),
        const SizedBox(height: 4),
        LocationSelector(controller: controller),

        const SizedBox(height: 18),

        Text(
          'Reason for Maintenance',
          style: TextStyle(
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: colorScheme.fontInverted,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller.descriptionController,
          maxLength: 200,
          minLines: 4,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          style: TextStyle(letterSpacing: 0, color: colorScheme.fontInverted),
          decoration: _inputDecoration(context).copyWith(
            hintText: 'Describe the issue...',
            hintStyle: TextStyle(
              letterSpacing: 0,
              color: colorScheme.fontSecondary,
            ),
          ),
        ),

        const SizedBox(height: 18),
        Text(
          'Attach a Photo (Optional)',
          style: TextStyle(
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: colorScheme.fontInverted,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => controller.pickImage(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: 140),
              padding: controller.selectedImage == null
                  ? const EdgeInsets.all(16)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.fontSecondary,
                  width: 1.5,
                ),
              ),
              child: controller.selectedImage == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 40,
                          color: colorScheme.fontSecondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to take or upload a photo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            letterSpacing: 0,
                            color: colorScheme.fontSecondary,
                          ),
                        ),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        controller.selectedImage!,
                        height: 140,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
            ),
          ),
        ),

        if (controller.attemptedSubmit && !controller.isFormValid)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.brightness == Brightness.dark
                      ? colorScheme.fontSecondary
                      : colorScheme.error,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Please fill in all fields',
                    style: TextStyle(
                      letterSpacing: 0,
                      color: colorScheme.brightness == Brightness.dark
                          ? colorScheme.fontSecondary
                          : colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
