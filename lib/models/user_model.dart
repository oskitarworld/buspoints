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
  final String role;
  final String status;
  final int approvedPoisCount;
  final List<Subscription> subscriptionHistory;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.status,
    this.approvedPoisCount = 0,
    this.subscriptionHistory = const [], // Default to an empty list
  });

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

    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? data['displayName'] ?? 'Nombre no disponible',
      role: data['role'] ?? 'user',
      status: data['status'] ?? 'pending',
      approvedPoisCount: data['approvedPoisCount'] ?? 0,
      subscriptionHistory: history,
    );
  }

  // Method to convert UserModel to a map for Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'role': role,
      'status': status,
      'approvedPoisCount': approvedPoisCount,
      // Convert the list of Subscription objects to a list of maps.
      'subscriptionHistory':
          subscriptionHistory.map((sub) => sub.toMap()).toList(),
    };
  }
}
