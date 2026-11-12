import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/repositories/contact_repository.dart';
import '../../contacts/providers/sender_provider.dart';

enum DuplicateHandling { skip, keepBoth, merge }

class ReceiverState {
  const ReceiverState({
    this.receivedContacts = const [],
    this.selectedIds = const {},
    this.searchQuery = '',
    this.duplicateHandling = DuplicateHandling.skip,
    this.isImporting = false,
    this.importProgress = 0,
    this.savedCount = 0,
    this.skippedCount = 0,
    this.failedCount = 0,
    this.mergedCount = 0,
    this.savedContacts = const [],
    this.skippedContacts = const [],
    this.failedContacts = const [],
    this.mergedContacts = const [],
    this.errorMessage,
  });

  final List<AppContact> receivedContacts;
  final Set<String> selectedIds;
  final String searchQuery;
  final DuplicateHandling duplicateHandling;
  final bool isImporting;
  final int importProgress;
  final int savedCount;
  final int skippedCount;
  final int failedCount;
  final int mergedCount;
  final List<AppContact> savedContacts;
  final List<AppContact> skippedContacts;
  final List<AppContact> failedContacts;
  final List<AppContact> mergedContacts;
  final String? errorMessage;

  int get duplicateCount => receivedContacts.where((c) => c.isDuplicate).length;

  List<AppContact> get filteredContacts {
    if (searchQuery.trim().isEmpty) return receivedContacts;
    final query = searchQuery.toLowerCase();
    return receivedContacts.where((c) {
      return c.name.toLowerCase().contains(query) ||
          c.phone.toLowerCase().contains(query) ||
          (c.email?.toLowerCase().contains(query) ?? false) ||
          (c.organization?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  List<AppContact> get selectedContacts {
    return receivedContacts.where((c) => selectedIds.contains(c.id)).toList();
  }

  ReceiverState copyWith({
    List<AppContact>? receivedContacts,
    Set<String>? selectedIds,
    String? searchQuery,
    DuplicateHandling? duplicateHandling,
    bool? isImporting,
    int? importProgress,
    int? savedCount,
    int? skippedCount,
    int? failedCount,
    int? mergedCount,
    List<AppContact>? savedContacts,
    List<AppContact>? skippedContacts,
    List<AppContact>? failedContacts,
    List<AppContact>? mergedContacts,
    String? errorMessage,
  }) {
    return ReceiverState(
      receivedContacts: receivedContacts ?? this.receivedContacts,
      selectedIds: selectedIds ?? this.selectedIds,
      searchQuery: searchQuery ?? this.searchQuery,
      duplicateHandling: duplicateHandling ?? this.duplicateHandling,
      isImporting: isImporting ?? this.isImporting,
      importProgress: importProgress ?? this.importProgress,
      savedCount: savedCount ?? this.savedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      failedCount: failedCount ?? this.failedCount,
      mergedCount: mergedCount ?? this.mergedCount,
      savedContacts: savedContacts ?? this.savedContacts,
      skippedContacts: skippedContacts ?? this.skippedContacts,
      failedContacts: failedContacts ?? this.failedContacts,
      mergedContacts: mergedContacts ?? this.mergedContacts,
      errorMessage: errorMessage,
    );
  }
}

class ReceiverNotifier extends StateNotifier<ReceiverState> {
  ReceiverNotifier(this._repository) : super(const ReceiverState());

  final ContactRepository _repository;

  ReceiverState get currentState => state;

  void setReceivedContacts(List<AppContact> contacts) {
    // By default, select all non-duplicate contacts or all contacts if none are duplicates
    final allIds = contacts.map((c) => c.id).toSet();
    state = state.copyWith(
      receivedContacts: contacts,
      selectedIds: allIds,
      isImporting: false,
      importProgress: 0,
      savedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      mergedCount: 0,
      savedContacts: const [],
      skippedContacts: const [],
      failedContacts: const [],
      mergedContacts: const [],
    );
  }

  void setDuplicateHandling(DuplicateHandling handling) {
    state = state.copyWith(duplicateHandling: handling);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void toggleContact(String id) {
    final nextSelected = Set<String>.from(state.selectedIds);
    if (nextSelected.contains(id)) {
      nextSelected.remove(id);
    } else {
      nextSelected.add(id);
    }
    state = state.copyWith(selectedIds: nextSelected);
  }

  void selectAll() {
    if (state.searchQuery.trim().isNotEmpty) {
      final filteredIds = state.filteredContacts.map((c) => c.id).toSet();
      state = state.copyWith(selectedIds: state.selectedIds.union(filteredIds));
    } else {
      final allIds = state.receivedContacts.map((c) => c.id).toSet();
      state = state.copyWith(selectedIds: allIds);
    }
  }

  void clearAll() {
    if (state.searchQuery.trim().isNotEmpty) {
      final filteredIds = state.filteredContacts.map((c) => c.id).toSet();
      state = state.copyWith(selectedIds: state.selectedIds.difference(filteredIds));
    } else {
      state = state.copyWith(selectedIds: {});
    }
  }

  void deselectDuplicates() {
    final nonDuplicates = state.receivedContacts
        .where((c) => !c.isDuplicate)
        .map((c) => c.id)
        .toSet();
    state = state.copyWith(selectedIds: nonDuplicates);
  }

  /// Batch inserts selected contacts to native device address book with merge support.
  Future<bool> importSelectedContacts() async {
    final toSave = state.selectedContacts;
    if (toSave.isEmpty) return false;

    state = state.copyWith(
      isImporting: true,
      importProgress: 0,
      errorMessage: null,
    );

    final List<AppContact> saved = [];
    final List<AppContact> merged = [];
    final List<AppContact> failed = [];
    final List<AppContact> skipped = state.receivedContacts
        .where((c) => !state.selectedIds.contains(c.id))
        .toList();

    try {
      for (int i = 0; i < toSave.length; i++) {
        final contact = toSave[i];
        if (contact.isDuplicate && state.duplicateHandling == DuplicateHandling.skip) {
          skipped.add(contact);
        } else if (contact.isDuplicate && state.duplicateHandling == DuplicateHandling.merge) {
          final success = await _repository.mergeContact(contact);
          if (success) {
            merged.add(contact);
          } else {
            failed.add(contact);
          }
        } else {
          final success = await _repository.insertContact(contact);
          if (success) {
            saved.add(contact);
          } else {
            failed.add(contact);
          }
        }
        state = state.copyWith(importProgress: i + 1);
      }

      state = state.copyWith(
        isImporting: false,
        savedCount: saved.length,
        skippedCount: skipped.length,
        failedCount: failed.length,
        mergedCount: merged.length,
        savedContacts: saved,
        skippedContacts: skipped,
        failedContacts: failed,
        mergedContacts: merged,
      );
      return true;
    } catch (e) {
      debugPrint('Error during batch import: $e');
      state = state.copyWith(
        isImporting: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  void reset() {
    state = const ReceiverState();
  }
}

final receiverProvider = StateNotifierProvider<ReceiverNotifier, ReceiverState>((ref) {
  final repository = ref.watch(contactRepositoryProvider);
  return ReceiverNotifier(repository);
});
