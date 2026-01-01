import 'package:cloud_firestore/cloud_firestore.dart';

// A helper class to represent a single subscription period.
class Subscription {
  final DateTime startDate;
  final DateTime endDate;

  Subscription({required this.startDate, required this.endDate});

  // Convert a Subscription object to a map for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
    };
  }

  // Create a Subscription object from a map from Firestore.
  factory Subscription.fromMap(Map<String, dynamic> map) {
    return Subscription(
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
    );
  }
}

class UserModel {
  final String uid;
  final String email;
  final String name;
  final String phone;
  final String role;
  final String status;
  final int approvedPoisCount;
  final List<Subscription> subscriptionHistory;
  final bool subscriptionFrozen;
  final String? trialStatus;
  final DateTime? trialExpiry;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    required this.status,
    this.approvedPoisCount = 0,
    this.subscriptionHistory = const [], // Default to an empty list
    this.subscriptionFrozen = false,
    this.trialStatus,
    this.trialExpiry,
  });

  // Check if the user currently has an active trial
  bool get isTrialActive {
    if (trialStatus == null || trialExpiry == null) return false;
    return trialStatus == 'active' && trialExpiry!.isAfter(DateTime.now());
  }

  // A getter to find the latest subscription end date.
  DateTime? get latestSubscriptionEndDate {
    if (subscriptionHistory.isEmpty) {
      return null;
    }
    // Sort history to find the most recent subscription end date
    final sortedHistory = List<Subscription>.from(subscriptionHistory)
      ..sort((a, b) => b.endDate.compareTo(a.endDate));
    return sortedHistory.first.endDate;
  }

  // A getter to easily check if the subscription is currently active.
  bool get isSubscriptionActive {
    final endDate = latestSubscriptionEndDate;
    if (endDate == null) {
      return false;
    }
    return endDate.isAfter(DateTime.now());
  }

  // Factory constructor to create a UserModel from a Firestore document.
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Read the subscription history from Firestore.
    List<Subscription> history = [];
    if (data['subscriptionHistory'] is List) {
      history = (data['subscriptionHistory'] as List)
          .map((item) => Subscription.fromMap(item as Map<String, dynamic>))
          .toList();
    }

    // Backwards-compatibility: if no subscriptionHistory exists but explicit
    // `subscriptionStart`/`subscriptionEnd` (or `subscriptionEndDate`) fields
    // are present, create a single-entry history so UI and checks work.
    if (history.isEmpty) {
      Timestamp? startTs;
      Timestamp? endTs;
      if (data['subscriptionStart'] is Timestamp) {
        startTs = data['subscriptionStart'] as Timestamp;
      }
      if (data['subscriptionEnd'] is Timestamp) {
        endTs = data['subscriptionEnd'] as Timestamp;
      }
      // older code/path might have used subscriptionEndDate
      if (endTs == null && data['subscriptionEndDate'] is Timestamp) {
        endTs = data['subscriptionEndDate'] as Timestamp;
      }

      if (startTs != null || endTs != null) {
        final start = (startTs ?? endTs)!.toDate();
        final end = (endTs ?? startTs)!.toDate();
        history = [Subscription(startDate: start, endDate: end)];
      }
    }

    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? data['displayName'] ?? 'Nombre no disponible',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'user',
      status: data['status'] ?? 'pending',
      approvedPoisCount: data['approvedPoisCount'] ?? 0,
      subscriptionHistory: history,
      subscriptionFrozen: data['subscriptionFrozen'] ?? false,
      trialStatus: data['trialStatus'] as String?,
      trialExpiry: data['trialExpiry'] is Timestamp ? (data['trialExpiry'] as Timestamp).toDate() : null,
    );
  }

  // Method to convert UserModel to a map for Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'phone': phone,
      'role': role,
      'status': status,
      'approvedPoisCount': approvedPoisCount,
      // Convert the list of Subscription objects to a list of maps.
      'subscriptionHistory':
          subscriptionHistory.map((sub) => sub.toMap()).toList(),
      'subscriptionFrozen': subscriptionFrozen,
      if (trialStatus != null) 'trialStatus': trialStatus,
      if (trialExpiry != null) 'trialExpiry': Timestamp.fromDate(trialExpiry!),
    };
  }
}
