import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  static final _auth = FirebaseAuth.instance;
  static final _firestore = FirebaseFirestore.instance;
  static String? token;
  static Map<String, dynamic>? user;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProfiles() =>
      _users.snapshots();

  Future<void> updateUserRole(
    String userId,
    String role, {
    String? restaurantName,
  }) async {
    if (!['customer', 'seller', 'driver'].contains(role)) {
      throw const ApiException('Choose a valid account role.');
    }
    if (role == 'seller' && (restaurantName == null || restaurantName.trim().isEmpty)) {
      throw const ApiException('A seller must be assigned a restaurant name.');
    }

    await _users.doc(userId).update({
      'role': role,
      'restaurantName': role == 'seller'
          ? restaurantName!.trim()
          : FieldValue.delete(),
    });
  }

  Future<String> login({required String email, required String password}) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final authUser = credential.user;
      if (authUser == null) {
        throw const ApiException('Firebase did not return a signed-in user.');
      }
      return await _loadSession(authUser);
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    } on FirebaseException catch (error) {
      throw ApiException(_firebaseError(error));
    }
  }

  Future<String> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String role = 'customer',
    String? restaurantName,
  }) async {
    if (!['customer', 'seller', 'driver'].contains(role)) {
      throw const ApiException('Choose a valid account role.');
    }
    if (role == 'seller' &&
        (restaurantName == null || restaurantName.trim().isEmpty)) {
      throw const ApiException('Please enter your restaurant name.');
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final authUser = credential.user;
      if (authUser == null) {
        throw const ApiException('Firebase did not create an account.');
      }
      await authUser.updateDisplayName(name);
      await _users.doc(authUser.uid).set({
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        if (role == 'seller') 'restaurantName': restaurantName!.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return await _loadSession(authUser);
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    } on FirebaseException catch (error) {
      throw ApiException(_firebaseError(error));
    }
  }

  Future<Map<String, dynamic>?> restoreSession() async {
    try {
      final authUser = _auth.currentUser;
      if (authUser == null) return null;
      await _loadSession(authUser);
      return ApiService.user;
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    } on FirebaseException catch (error) {
      throw ApiException(_firebaseError(error));
    }
  }

  Future<Map<String, dynamic>> profile() async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      throw const ApiException('You are not signed in.');
    }

    try {
      await _loadSession(authUser);
      return ApiService.user!;
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    } on FirebaseException catch (error) {
      throw ApiException(_firebaseError(error));
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      token = null;
      user = null;
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String email,
    required String phone,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      throw const ApiException('You are not signed in.');
    }

    try {
      final emailVerificationPending = authUser.email != email;
      if (emailVerificationPending) {
        await authUser.verifyBeforeUpdateEmail(email);
      }
      await authUser.updateDisplayName(name);
      await _users.doc(authUser.uid).update({
        'name': name,
        'phone': phone,
      });
      user = {
        ...?user,
        'name': name,
        'email': authUser.email ?? email,
        'phone': phone,
        'emailVerificationPending': emailVerificationPending,
      };
      token = await authUser.getIdToken() ?? token;
      return user!;
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    } on FirebaseException catch (error) {
      throw ApiException(_firebaseError(error));
    }
  }

  Future<void> deleteAccount() async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      throw const ApiException('You are not signed in.');
    }

    final profileReference = _users.doc(authUser.uid);
    try {
      final profileSnapshot = await profileReference.get();
      if (profileSnapshot.exists) await profileReference.delete();
      try {
        await authUser.delete();
      } on FirebaseAuthException {
        if (profileSnapshot.exists) {
          await profileReference.set(profileSnapshot.data()!);
        }
        rethrow;
      }
      token = null;
      user = null;
    } on FirebaseAuthException catch (error) {
      throw ApiException(_authError(error));
    } on FirebaseException catch (error) {
      throw ApiException(_firebaseError(error));
    }
  }

  Future<String> _loadSession(User authUser) async {
    final profileReference = _users.doc(authUser.uid);
    final snapshot = await profileReference.get();
    final profile = snapshot.data() ?? <String, dynamic>{};

    if (!snapshot.exists) {
      profile.addAll({
        'name': authUser.displayName ?? '',
        'email': authUser.email ?? '',
        'phone': authUser.phoneNumber ?? '',
        'role': 'customer',
      });
      await profileReference.set({
        ...profile,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else if (authUser.email != null &&
        profile['email'] != authUser.email) {
      await profileReference.update({'email': authUser.email});
      profile['email'] = authUser.email;
    }

    profile['uid'] = authUser.uid;
    user = profile;
    token = await authUser.getIdToken() ?? '';
    return token!;
  }

  String _authError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'requires-recent-login':
        return 'Please sign in again before making this change.';
      case 'network-request-failed':
        return 'Unable to connect. Check your internet connection.';
      default:
        return error.message ?? 'Firebase Authentication failed.';
    }
  }

  String _firebaseError(FirebaseException error) {
    return error.message ?? 'Unable to access your Firebase data.';
  }
}
