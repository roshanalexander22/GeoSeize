import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('username_$uid')) return true;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data()!.containsKey('username')) {
        await prefs.setString('username_$uid', doc.data()!['username']);
        return true;
      }
    } catch (e) {
      print('Firestore error: $e');
    }
    return false;
  }

  // Get username
  Future<String?> getUsername(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('username_$uid')) {
      return prefs.getString('username_$uid');
    }

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final name = doc.data()?['username'] as String?;
        if (name != null) await prefs.setString('username_$uid', name);
        return name;
      }
    } catch (e) {
      print('Firestore error: $e');
    }
    return null;
  }

  // Set username
  Future<void> setUsername(String uid, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username_$uid', username);

    try {
      await _firestore.collection('users').doc(uid).set({
        'username': username,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Firestore error: $e');
    }
  }
}
