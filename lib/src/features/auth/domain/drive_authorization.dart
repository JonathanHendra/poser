const driveFileScope = 'https://www.googleapis.com/auth/drive.file';

abstract interface class DriveAuthorization {
  Future<String?> driveToken(String uid, {bool interactive = false});
  Future<void> invalidateDriveToken(String token);
}
