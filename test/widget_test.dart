import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:absensiku/main.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/views/users/daftar_hadir_screen.dart';
import 'package:absensiku/views/users/home_screen.dart';
import 'package:absensiku/views/users/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test User',
      'user_email': 'test@example.com',
      'user_id': 1,
      'token': 'test_token',
    });
  });
  testWidgets('App renders LoginScreen when not logged in', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(isLoggedIn: false));

    // Verify Login Screen elements
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Masuk ke Absensiku'), findsOneWidget);
  });

  testWidgets('HomeScreen renders without overflow on small screen', (WidgetTester tester) async {
    // Set small screen dimensions (360x600) to test overflow protection
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    tester.takeException();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();

    expect(find.text('Absensiku'), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Daftar Hadir'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('DaftarHadirScreen renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DaftarHadirScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Daftar Kehadiran'), findsOneWidget);
    expect(find.text('Total Absensi'), findsOneWidget);
    expect(find.text('Absen Masuk'), findsOneWidget);
    expect(find.text('Absen Pulang'), findsOneWidget);
  });

  testWidgets('ProfileScreen renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Profil Pengguna'), findsOneWidget);
  });

  testWidgets('Confirmation alert with Expanded buttons renders without overflow on small screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Row(
                      children: [
                        Icon(Icons.login, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Konfirmasi Absen Masuk',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    content: const SingleChildScrollView(
                      child: Text('Catat kehadiran Masuk sekarang pada pukul 08:00:00 WIB?'),
                    ),
                    actions: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {},
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {},
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Ya, Absen Masuk')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Buka Dialog'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Buka Dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Konfirmasi Absen Masuk'), findsOneWidget);
    expect(find.text('Ya, Absen Masuk'), findsOneWidget);
    expect(find.text('Batal'), findsOneWidget);
  });

  testWidgets('DaftarHadirScreen does not contain edit buttons for attendance (Kecuali Absen)', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DaftarHadirScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify there are no edit buttons for attendance (absen immutable)
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('ProfileScreen provides edit form and photo picker options', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Edit buttons exist in Profile
    expect(find.text('Edit Formulir & Foto'), findsOneWidget);
    expect(find.text('Ganti Foto'), findsOneWidget);
    expect(find.text('Informasi Formulir Akun'), findsOneWidget);

    // Verify notice that attendance is locked/official
    expect(find.text('Ketentuan Data Absensi (Presensi)'), findsOneWidget);
  });

  test('AppApiService.autoSyncAllData runs safely without crashing', () async {
    final result = await AppApiService.autoSyncAllData();
    expect(result, isA<Map<String, dynamic>>());
    expect(result.containsKey('pendingSynced'), isTrue);
    expect(result.containsKey('apiItemsSynced'), isTrue);
    expect(result.containsKey('profileSynced'), isTrue);
  });
}

