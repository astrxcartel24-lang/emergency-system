import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LocationCard extends StatelessWidget {
  final String address;
  final bool isLoading;
  final VoidCallback onRefresh;

  const LocationCard({
    super.key,
    required this.address,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacitySafe(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.location_on,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: isLoading
                ? const Text(
                    'Inapata mahali...',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  )
                : Text(
                    address.isEmpty ? 'Mahali hakupatikana' : address,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.dark,
                    ),
                  ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(
              Icons.refresh,
              color: AppColors.muted,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
