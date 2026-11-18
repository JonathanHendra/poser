# Fase 2: Google Sign-In langsung

Keputusan terbaru: autentikasi memakai google_sign_in tanpa Firebase atau backend.
Identity UID adalah Google account ID. Penyelesaian onboarding kini ditentukan
dari profil SQLite yang tersimpan per Google account ID.
GoogleAuthRepository menghubungkan SDK; AuthController dan route guard menjaga UI.

## Environment

`.env` sudah dibuat dan diabaikan Git; `.env.example` adalah template publik.
Flutter memuat `.env` sebagai asset menggunakan flutter_dotenv. Isi hanya OAuth
client ID publik. Asset dapat dibaca dari build: jangan memasukkan client secret,
access token, refresh token, service account, atau kredensial server.

```dotenv
GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

1. Google Cloud Console: konfigurasi Google Auth Platform (branding, audience dan
   test users jika aplikasi masih testing). Buat OAuth client untuk platform target.
2. Web: client tipe Web application. Authorized JavaScript origins harus mencakup
   `http://localhost:8081` dan origin deployment (skema, host dan port harus cocok).
   Masukkan ID ke GOOGLE_WEB_CLIENT_ID dan GOOGLE_SERVER_CLIENT_ID.
3. Android: buat client tipe Android untuk package `com.posumkm.pos_umkm` dan SHA-1
   signing certificate debug/release. GOOGLE_SERVER_CLIENT_ID memakai client tipe
   Web application dari project yang sama. Tidak membutuhkan google-services.json.
4. iOS: buat client tipe iOS dengan bundle identifier Runner. Isi GOOGLE_IOS_CLIENT_ID
   dan tambahkan URL scheme ID terbalik ke ios/Runner/Info.plist. Contoh client
   `123-abc.apps.googleusercontent.com` memakai scheme
   `com.googleusercontent.apps.123-abc`. File GoogleService-Info.plist tidak diperlukan.
5. Setelah mengisi `.env`, restart/build ulang app. Jalankan
   `flutter run -d web-server --web-port 8081` untuk web.

Web memakai tombol resmi Google Identity Services; native memakai authenticate.
Client ID kosong memblokir login dengan pesan konfigurasi yang jelas.

## Sesi, offline, dan akun

### Diagnosis Android pada mesin pengembangan ini

Log Google pada emulator menunjukkan aplikasi belum terdaftar untuk OAuth2.0.
Di Google Cloud project yang sama dengan Web client ID dalam `.env`, buat/perbarui
OAuth client tipe Android dengan:

- Package name: `com.posumkm.pos_umkm`
- SHA-1 debug: `F3:C9:FF:FE:B2:71:F5:E9:85:3E:73:6D:D0:53:EB:94:5B:11:20:37`

Fingerprint ini dibaca dari `~/.android/debug.keystore` mesin ini. Sertifikat
release atau mesin lain dapat berbeda. ID client Android tidak dimasukkan ke
GOOGLE_SERVER_CLIENT_ID; variabel tersebut tetap memakai Web client ID.
Mengisi `.env` saja tidak mendaftarkan aplikasi Android ke Google Cloud.
Setelah mengubah `.env`, hentikan dan jalankan ulang aplikasi agar asset diperbarui.

### Kebijakan sesi

Restorasi menggunakan attemptLightweightAuthentication dari SDK. Jika tidak ada
sesi SDK yang berhasil dipulihkan, pengguna harus login. Tidak ada token atau
identitas buatan yang disimpan dalam SharedPreferences sebagai bukti autentikasi.
Status onboarding kini ditentukan dari profil usaha SQLite (lihat phase-2-real-data.md).
Saat aplikasi aktif, identitas yang
telah login tidak dibatalkan hanya karena request lain gagal jaringan.

Tanpa Firebase/backend, Google GIS web tidak menyediakan sesi aplikasi persisten
atau refresh otomatis ID token. Restart offline belum dijamin memulihkan sesi.
Kebijakan sesi lokal aman untuk cold start offline perlu dikembangkan sebelum
persyaratan offline-first dinyatakan selesai. Transaksi lokal masih menunggu Fase 3.

Logout memakai SDK signOut. Verifikasi native meminta login akun yang sama;
akun berbeda menyebabkan logout. Verifikasi web mengarahkan kembali ke tombol
resmi Google. Putuskan akses menggunakan disconnect untuk mencabut izin aplikasi
tanpa menghapus profil usaha SQLite. Ini tidak menghapus akun Google atau data usaha.
Tidak ada akun backend yang perlu dihapus. Penghapusan data usaha akan memerlukan
database dan kebijakan retensi pada fase berikutnya.

## Pengujian

Jalankan format, analyze, unit/widget tests, dan build web. Login Google sebenarnya
masih memerlukan OAuth client ID. Uji native restore/restart, batal login, akun
berbeda saat verifikasi, logout, disconnect, serta origin dan tombol GIS di browser.

Referensi: https://pub.dev/packages/google_sign_in,
https://pub.dev/packages/google_sign_in_android,
https://pub.dev/packages/google_sign_in_web.
