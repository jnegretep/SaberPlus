import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class ProfileAvatarWidget extends StatelessWidget {
  final File? selectedImage;
  final String? selectedAvatarAsset;
  final VoidCallback onPickImage;

  const ProfileAvatarWidget({
    Key? key,
    required this.selectedImage,
    required this.selectedAvatarAsset,
    required this.onPickImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        CircleAvatar(
          radius: 45,
          backgroundColor: AppColors.stepInactive,
          backgroundImage: selectedImage != null
              ? FileImage(selectedImage!)
              : (selectedAvatarAsset != null
                  ? AssetImage(selectedAvatarAsset!)
                  : null) as ImageProvider<Object>?,
          child: (selectedImage == null && selectedAvatarAsset == null)
              ? Icon(Icons.person, size: 50, color: AppColors.textOnPrimary)
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 4,
          child: InkWell(
            onTap: onPickImage,
            child: const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.subjectTeal,
              child: Icon(Icons.camera_alt, color: AppColors.textOnPrimary, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}
