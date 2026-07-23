import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _googleSignIn = GoogleSignIn(scopes: ['email']);

  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;
  String? get displayName => _auth.currentUser?.displayName;
  String? get email => _auth.currentUser?.email;

  Future<String> ensureHousehold() async {
    var user = _auth.currentUser;
    user ??= (await _auth.signInAnonymously()).user;
    final uid = user!.uid;

    final userDoc = _db.collection('users').doc(uid);
    final userSnap = await userDoc.get();

    String householdId;
    if (userSnap.exists && userSnap.data()?['householdId'] != null) {
      householdId = userSnap.data()!['householdId'] as String;
    } else {
      final householdRef = _db.collection('households').doc();
      await householdRef.set({
        'name': 'הבית שלי',
        'members': [uid],
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await userDoc.set({'householdId': householdRef.id});
      householdId = householdRef.id;
    }

    await _updateMemberProfile(householdId, uid);
    return householdId;
  }

  Future<void> _updateMemberProfile(String householdId, String uid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.doc('households/$householdId').update({
      'memberProfiles.$uid': {
        'displayName': user.displayName ?? 'אורח',
        'email': user.email,
        'isAnonymous': user.isAnonymous,
      },
    });
  }

  /// Links the current anonymous account to Google, preserving the existing
  /// household. If that Google account already has its own Firebase user,
  /// signs into that account instead (its own household takes over).
  Future<String> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('ההתחברות בוטלה');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    try {
      await _auth.currentUser?.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        await _auth.signInWithCredential(credential);
      } else {
        rethrow;
      }
    }

    return ensureHousehold();
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<Map<String, dynamic>?> getHousehold(String householdId) async {
    final doc = await _db.doc('households/$householdId').get();
    return doc.data();
  }

  Future<void> renameHousehold(String householdId, String name) async {
    await _db.doc('households/$householdId').update({'name': name});
  }

  /// Joins an existing household by its ID. The current user leaves any
  /// household they're already a member of. Returns the new householdId.
  Future<String> joinHousehold(String targetHouseholdId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('לא מחובר');
    final uid = user.uid;

    final targetRef = _db.doc('households/$targetHouseholdId');
    final targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
      throw Exception('קוד הזמנה לא נמצא');
    }

    await targetRef.update({
      'members': FieldValue.arrayUnion([uid]),
    });
    await _db.collection('users').doc(uid).set({'householdId': targetHouseholdId});
    await _updateMemberProfile(targetHouseholdId, uid);

    return targetHouseholdId;
  }

  /// Removes the current user from a household's member list. Does not
  /// create a replacement household — call ensureHousehold() afterwards.
  Future<void> leaveHousehold(String householdId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    await _db.doc('households/$householdId').update({
      'members': FieldValue.arrayRemove([uid]),
      'memberProfiles.$uid': FieldValue.delete(),
    });
    await _db.collection('users').doc(uid).delete();
  }
}
