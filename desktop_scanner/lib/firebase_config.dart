/// Firebase project coordinates, copied from the mobile app's
/// `firebase_options.dart`. The Web API key is not a secret — it identifies the
/// project; access is controlled by the Firestore security rules.
class FirebaseConfig {
  static const projectId = 'home-inventory-32dd1';
  static const apiKey = 'AIzaSyA3HRxJe36Z3ngQMa0FK5vE4UO4Ht7-9lE';

  static const identityBase = 'https://identitytoolkit.googleapis.com/v1';
  static const secureTokenBase = 'https://securetoken.googleapis.com/v1';
  /// Resource path of the default database's document root. Fully-qualified
  /// document names in `:commit` writes are built from this.
  static const documentsPath =
      'projects/$projectId/databases/(default)/documents';

  static const firestoreBase =
      'https://firestore.googleapis.com/v1/$documentsPath';
}
