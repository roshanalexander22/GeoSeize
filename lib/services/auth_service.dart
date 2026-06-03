import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with Email and Password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Sign up with Email and Password
  Future<UserCredential> signUpWithEmail(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await _googleSignIn.initialize();
      // Trigger the authentication flow
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // Create a new credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      print('Error signing in with Google: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      print('Google sign out error: $e');
    }
    await _auth.signOut();
  }

  // Delete account
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user != null) {
      // Delete user document in Firestore
      await _firestore.collection('users').doc(user.uid).delete();
      // Delete user from Firebase Auth
      await user.delete();
      // Sign out to clean up local state
      await signOut();
    }
  }

  // Check if username exists
  Future<bool> hasUsername(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists && doc.data()!.containsKey('username');
  }

  // Get username
  Future<String?> getUsername(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return doc.data()?['username'] as String?;
    }
    return null;
  }

  // Set username
  Future<void> setUsername(String uid, String username) async {
    await _firestore.collection('users').doc(uid).set({
      'username': username,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
