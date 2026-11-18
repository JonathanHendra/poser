import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/database/app_database.dart';
import 'package:pos_umkm/src/core/domain/money.dart';
import 'package:pos_umkm/src/features/business/data/local_business_repository.dart';
import 'package:pos_umkm/src/features/business/domain/business_repository.dart';
import 'package:pos_umkm/src/features/cash_flow/data/cash_flow_repository.dart';
import 'package:pos_umkm/src/features/cloud/data/sqlite_backup.dart';

const profile = BusinessProfile(
  businessType: 'Warung',
  ownerName: 'Pemilik',
  address: 'Alamat',
  phone: '08123',
  storeName: 'Utama',
);
void main() {
  late AppDatabase db;
  late CashFlowRepository repo;
  late int store;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = CashFlowRepository(db);
    await LocalBusinessRepository(db).activate('a', profile);
    store = (await repo.stores('a')).first.$1;
  });
  tearDown(() => db.close());
  Future<int> save(CashFlowKind kind, int amount, {CashFlowEntry? initial}) =>
      repo.save(
        'a',
        kind: kind,
        storeId: store,
        category: 'Operasional',
        description: 'Catatan',
        amount: Money(amount),
        date: DateTime.now(),
        initial: initial,
      );
  test(
    'manual income and expenses do not create cashier sales and enter backup',
    () async {
      await save(CashFlowKind.income, 500000);
      await save(CashFlowKind.expense, 100000);
      final entries = await repo.list('a');
      expect(entries, hasLength(2));
      expect(
        entries
            .where((entry) => entry.kind == CashFlowKind.income)
            .single
            .amount,
        Money(500000),
      );
      expect(await db.customSelect('SELECT * FROM sales').get(), isEmpty);
      expect(
        await db
            .customSelect(
              "SELECT * FROM cloud_outbox WHERE entity IN ('expenses','income_entries')",
            )
            .get(),
        hasLength(2),
      );
      final snapshot = await captureSqlite(db, 'a');
      expect(
        snapshot.tables
            .singleWhere((table) => table.name == 'income_entries')
            .rows,
        hasLength(1),
      );
      expect(
        snapshot.tables.singleWhere((table) => table.name == 'expenses').rows,
        hasLength(1),
      );
    },
  );
  test('edit, change kind and delete preserve audit history', () async {
    await save(CashFlowKind.expense, 100000);
    await save(
      CashFlowKind.expense,
      150000,
      initial: (await repo.list('a')).single,
    );
    expect((await repo.list('a')).single.amount, Money(150000));
    await save(
      CashFlowKind.income,
      200000,
      initial: (await repo.list('a')).single,
    );
    expect((await repo.list('a')).single.kind, CashFlowKind.income);
    expect(await db.customSelect('SELECT * FROM expenses').get(), isEmpty);
    await repo.delete('a', (await repo.list('a')).single);
    expect(await repo.list('a'), isEmpty);
    expect(
      await db
          .customSelect(
            "SELECT * FROM audit_logs WHERE action LIKE 'cash_flow.%'",
          )
          .get(),
      hasLength(4),
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
  test('accounts cannot read, edit or use another store', () async {
    await LocalBusinessRepository(db).activate('b', profile);
    await save(CashFlowKind.income, 1);
    expect(await repo.list('b'), isEmpty);
    await expectLater(
      repo.delete('b', (await repo.list('a')).single),
      throwsStateError,
    );
    await expectLater(
      repo.save(
        'a',
        kind: CashFlowKind.expense,
        storeId: (await repo.stores('b')).first.$1,
        category: 'Operasional',
        description: 'Catatan',
        amount: Money(1),
        date: DateTime.now(),
      ),
      throwsStateError,
    );
    expect(await repo.list('a'), hasLength(1));
  });
  test('invalid entry rolls back all financial and audit rows', () async {
    await expectLater(save(CashFlowKind.expense, 0), throwsFormatException);
    await expectLater(save(CashFlowKind.income, -1), throwsFormatException);
    expect(await repo.list('a'), isEmpty);
    expect(
      await db
          .customSelect(
            "SELECT * FROM audit_logs WHERE action LIKE 'cash_flow.%'",
          )
          .get(),
      isEmpty,
    );
  });
  test(
    'schema 9 snapshot restores into schema 10 without losing legacy data',
    () async {
      await save(CashFlowKind.expense, 12345);
      final captured = await captureSqlite(db, 'a');
      final previous = SqliteSnapshot(
        'a',
        9,
        captured.tables
            .where((table) => table.name != 'income_entries')
            .toList(),
        captured.indexes
            .where((sql) => !sql.contains('income_entries'))
            .toList(),
        0,
      );
      final codec = SqliteBackupCodec();
      final bytes = await codec.encode(previous);
      final decoded = await codec.decode(bytes, 'a', db.schemaVersion);
      await save(CashFlowKind.income, 1000);
      await restoreSqlite(db, decoded, 'a');
      expect((await repo.list('a')).single.amount, Money(12345));
      expect((await repo.list('a')).single.kind, CashFlowKind.expense);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
}
