import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/card_box.dart';
import '../../../core/widgets/header.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/search_box.dart';
import '../../../core/widgets/shell.dart';
import '../providers/sender_provider.dart';
import 'review_screen.dart';
import 'widgets/contact_row.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(senderProvider).searchQuery,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final senderState = ref.watch(senderProvider);
    final senderNotifier = ref.read(senderProvider.notifier);
    final filtered = senderState.filteredContacts;
    final selectedIds = senderState.selectedIds;

    return Shell(
      child: Column(
        children: [
          const Header(title: 'Send contacts'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                  // Handle Permission Denied State
                  if (senderState.permissionDenied) ...[
                    Expanded(
                      child: Center(
                        child: CardBox(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.contacts_outlined,
                                size: 54,
                                color: AppColors.accent,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Contacts Permission Needed',
                                style: TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Qiwii requires contacts access so you can select which contacts you wish to transfer.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.slate,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () => senderNotifier.loadContacts(),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try Again'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => senderNotifier.openSettings(),
                                child: const Text(
                                  'Open App Settings',
                                  style: TextStyle(
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else if (senderState.isLoading) ...[
                    // Loading Shimmer / Spinner
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppColors.accent),
                            SizedBox(height: 16),
                            Text(
                              'Loading contacts...',
                              style: TextStyle(
                                color: AppColors.slate,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Normal Contact List View
                    SearchBox(
                      controller: _searchController,
                      onChanged: (q) => senderNotifier.setSearchQuery(q),
                      hint: 'Search by name, number, or email',
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final allFilteredSelected = filtered.isNotEmpty &&
                            filtered.every((c) => selectedIds.contains(c.id));
                        final isFiltering = senderState.searchQuery.trim().isNotEmpty;

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${selectedIds.length} of ${senderState.contacts.length} selected',
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                if (allFilteredSelected) {
                                  senderNotifier.clearAll();
                                } else {
                                  senderNotifier.selectAll();
                                }
                              },
                              child: Text(
                                allFilteredSelected
                                    ? (isFiltering ? 'Deselect matches' : 'Clear all')
                                    : (isFiltering ? 'Select all matches' : 'Select all'),
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.person_search,
                                    size: 48,
                                    color: AppColors.slate,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    senderState.contacts.isEmpty
                                        ? 'No contacts found on device'
                                        : 'No matching contacts for "${_searchController.text}"',
                                    style: const TextStyle(
                                      color: AppColors.slate,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                              itemBuilder: (_, index) {
                                final contact = filtered[index];
                                return ContactRow(
                                  contact: contact,
                                  selected: selectedIds.contains(contact.id),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    senderNotifier.toggleContact(contact.id);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!senderState.permissionDenied && !senderState.isLoading)
            PrimaryButton(
              label: 'Continue',
              icon: Icons.arrow_forward,
              onPressed: () {
                if (selectedIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least one contact to transfer.'),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReviewScreen(ids: selectedIds.toList()),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
