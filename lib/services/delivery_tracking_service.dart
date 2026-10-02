import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DeliveryTrackingService {
  DeliveryTrackingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestoreOverride = firestore,
      _authOverride = auth;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String? get currentUserId {
    try {
      return _auth.currentUser?.uid;
    } on FirebaseException {
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>> get _orders =>
      _firestore.collection('orders');

  CollectionReference<Map<String, dynamic>> get _menuItems =>
      _firestore.collection('menuItems');

  String orderDocumentId(String orderNumber) =>
      orderNumber.replaceAll('#', '').replaceAll('/', '-');

  Future<String> saveMenuItem({
    required String restaurantName,
    required String name,
    required String description,
    required double price,
    required String category,
    bool available = true,
    String? imagePath,
  }) async {
    final normalizedName = restaurantName.trim();
    if (normalizedName.isEmpty) {
      throw StateError('Seller restaurant name is required.');
    }

    final id = '${normalizedName.trim().toLowerCase()}-${DateTime.now().millisecondsSinceEpoch}';
    await _menuItems.doc(id).set({
      'restaurantName': normalizedName,
      'name': name,
      'description': description,
      'price': price,
      'category': category,
      'available': available,
      'imagePath': imagePath ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> fetchMenuForRestaurant(
    String restaurantName,
  ) async {
    final normalizedName = restaurantName.trim();
    if (normalizedName.isEmpty) return const [];

    final snapshot = await _menuItems
        .where('restaurantName', isEqualTo: normalizedName)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((document) {
      final data = document.data();
      return {
        'id': document.id,
        ...data,
      };
    }).toList();
  }

  Future<void> updateMenuAvailability(String itemId, {required bool available}) async {
    await _menuItems.doc(itemId).update({
      'available': available,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> createOrder({
    required String orderNumber,
    required String restaurantName,
    required String deliveryAddress,
    required double total,
    required int itemCount,
    required String imagePath,
    required String status,
    double? destinationLatitude,
    double? destinationLongitude,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final user = _auth.currentUser!;

    final id = orderDocumentId(orderNumber);
    await _orders.doc(id).set({
      'customerId': userId,
      'customerName': user.displayName ?? '',
      'orderNumber': orderNumber,
      'restaurantName': restaurantName,
      'deliveryAddress': deliveryAddress,
      'destination': destinationLatitude == null || destinationLongitude == null
          ? null
          : GeoPoint(destinationLatitude, destinationLongitude),
      'total': total,
      'itemCount': itemCount,
      'imagePath': imagePath,
      'status': status,
      'driverId': null,
      'driverName': null,
      'courierLocation': null,
      'sellerLocation': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCustomerOrders() {
    final userId = currentUserId;
    if (userId == null) return const Stream.empty();
    return _orders.where('customerId', isEqualTo: userId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSellerOrders(
    String restaurantName,
  ) => _orders.where('restaurantName', isEqualTo: restaurantName).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchReadyOrders() =>
      _orders.where('status', isEqualTo: 'Ready').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchDriverOrders() {
    final userId = currentUserId;
    if (userId == null) return const Stream.empty();
    return _orders.where('driverId', isEqualTo: userId).snapshots();
  }

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<bool> getDriverAvailability() async {
    final userId = currentUserId;
    if (userId == null) return false;
    final snapshot = await _users.doc(userId).get();
    return (snapshot.data()?['availableForDeliveries'] as bool?) ?? false;
  }

  Future<void> updateDriverAvailability({required bool available}) async {
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('Sign in as a driver to update availability.');
    }

    await _users.doc(userId).update({
      'availableForDeliveries': available,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateStoreAvailability({required bool available}) async {
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('Sign in as a seller to update store availability.');
    }

    await _users.doc(userId).update({
      'storeOpen': available,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> getDriverDashboardMetrics() async {
    final userId = currentUserId;
    if (userId == null) {
      return {
        'earningsToday': 0.0,
        'completedThisWeek': 0,
        'rating': 4.9,
        'available': false,
      };
    }

    final ordersSnapshot = await _orders.where('driverId', isEqualTo: userId).get();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = today.subtract(const Duration(days: 7));

    double earningsToday = 0;
    int completedThisWeek = 0;

    for (final doc in ordersSnapshot.docs) {
      final data = doc.data();
      final total = (data['total'] as num?)?.toDouble() ?? 0;
      final status = data['status'] as String? ?? '';
      final createdAt = data['createdAt'];

      if (createdAt is Timestamp &&
          createdAt.toDate().isAfter(weekAgo) &&
          status == 'Delivered') {
        completedThisWeek++;
      }

      if (createdAt is Timestamp &&
          createdAt.toDate().isAfter(today) &&
          status == 'Delivered') {
        earningsToday += total;
      }
    }

    final profileSnapshot = await _users.doc(userId).get();
    final profile = profileSnapshot.data() ?? const <String, dynamic>{};
    final rating = (profile['rating'] as num?)?.toDouble() ?? 4.9;
    final available = (profile['availableForDeliveries'] as bool?) ?? false;

    return {
      'earningsToday': earningsToday,
      'completedThisWeek': completedThisWeek,
      'rating': rating,
      'available': available,
    };
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrder(String orderId) =>
      _orders.doc(orderId).snapshots();

  Future<void> updateSellerStatus(String orderId, String status) async {
    await _orders.doc(orderId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> claimOrder(String orderId, String driverName) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Sign in as a driver to accept work.');

    final order = _orders.doc(orderId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(order);
      final data = snapshot.data();
      if (data == null ||
          data['status'] != 'Ready' ||
          data['driverId'] != null) {
        throw StateError('This delivery has already been claimed.');
      }
      transaction.update(order, {
        'driverId': userId,
        'driverName': driverName,
        'status': 'On the way',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateLocation(
    String orderId,
    GeoPoint location, {
    required bool fromSeller,
  }) async {
    final field = fromSeller ? 'sellerLocation' : 'courierLocation';
    await _orders.doc(orderId).update({
      field: location,
      '${field}UpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markDelivered(String orderId) async {
    await _orders.doc(orderId).update({
      'status': 'Delivered',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelOrder(String orderId) async {
    await _orders.doc(orderId).update({
      'status': 'Cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
