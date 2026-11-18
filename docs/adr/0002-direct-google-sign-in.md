# ADR 0002: Google Sign-In langsung

Status: diterima atas instruksi pengguna; menggantikan rencana Firebase Auth.

Google SDK mengelola autentikasi platform. Konfigurasi client ID publik tersedia
di `.env`. Tidak ada backend atau Firebase. Authorization usaha tetap merupakan
tanggung jawab aplikasi, dan data operasional tetap akan memakai SQLite.

Konsekuensi: identitas memakai Google account ID, disconnect menggantikan
penghapusan akun Firebase, sesi web persisten dan cold start offline tidak boleh
dianggap tersedia dari SDK. Kebijakan sesi lokal aman diperlukan pada tahap
lanjutan. OAuth client secret tidak boleh dibundel bersama aplikasi.
